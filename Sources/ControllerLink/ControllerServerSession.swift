import Foundation
#if SWIFT_PACKAGE
  import SimulationDiagnostics
#endif

public actor ControllerServerSession {
  private let identity: ControllerIdentity
  private let pairingAuthority: PairingCodeAuthority
  private let authorizationStore: any ControllerAuthorizationStore
  private let commandHandler: any ControllerCommandHandling
  private let diagnostics: SimulationDiagnosticRecorder?
  private let now: @Sendable () -> Date
  private let makeAuthorization: @Sendable () throws -> ControllerAuthorization

  public init(
    identity: ControllerIdentity,
    pairingAuthority: PairingCodeAuthority,
    authorizationStore: any ControllerAuthorizationStore,
    commandHandler: any ControllerCommandHandling = UnavailableControllerCommandHandler(),
    now: @escaping @Sendable () -> Date = Date.init,
    makeAuthorization: @escaping @Sendable () throws -> ControllerAuthorization = {
      try ControllerAuthorization.generate()
    },
    diagnostics: SimulationDiagnosticRecorder? = nil
  ) {
    self.identity = identity
    self.pairingAuthority = pairingAuthority
    self.authorizationStore = authorizationStore
    self.commandHandler = commandHandler
    self.diagnostics = diagnostics
    self.now = now
    self.makeAuthorization = makeAuthorization
  }

  public func process(_ request: ControllerLinkRequest) async -> ControllerLinkResponse {
    await record(
      kind: "controller.link.request.received",
      requestID: request.requestID,
      fields: requestFields(request)
    )
    switch request {
    case .status(let requestID, let presentedAuthorization):
      guard
        let presentedAuthorization,
        await isAuthorized(presentedAuthorization)
      else {
        return await finish(
          .rejected(requestID: requestID, reason: .pairingRequired)
        )
      }
      return await finish(
        await processCommand(
          .status(requestID: requestID),
          expectedResult: .status
        )
      )

    case .pair(let requestID, let code):
      do {
        _ = try await pairingAuthority.redeem(
          code: code,
          presentedIdentity: identity,
          at: now()
        )
        let authorization = try makeAuthorization()
        try await authorizationStore.save(authorization)
        return await finish(
          .paired(requestID: requestID, authorization: authorization)
        )
      } catch let error as PairingCodeError {
        return await finish(
          .rejected(requestID: requestID, reason: map(error))
        )
      } catch {
        return await finish(
          .rejected(requestID: requestID, reason: .invalidRequest)
        )
      }

    case .apply(
      let requestID,
      let presentedAuthorization,
      let latitude,
      let longitude
    ):
      guard await isAuthorized(presentedAuthorization) else {
        return await finish(
          .rejected(requestID: requestID, reason: .authorizationFailed)
        )
      }
      guard
        latitude.isFinite,
        longitude.isFinite,
        (-90.0...90.0).contains(latitude),
        (-180.0...180.0).contains(longitude)
      else {
        return await finish(
          .failed(requestID: requestID, reason: .invalidCoordinate)
        )
      }
      return await finish(
        await processCommand(
          .apply(
            requestID: requestID,
            latitude: latitude,
            longitude: longitude
          ),
          expectedResult: .apply
        )
      )

    case .stop(let requestID, let presentedAuthorization):
      guard await isAuthorized(presentedAuthorization) else {
        return await finish(
          .rejected(requestID: requestID, reason: .authorizationFailed)
        )
      }
      return await finish(
        await processCommand(
          .stop(requestID: requestID),
          expectedResult: .stop
        )
      )
    }
  }

  private func record(
    kind: String,
    requestID: UUID,
    fields: SimulationDiagnosticFields
  ) async {
    guard let diagnostics else { return }
    await diagnostics.record(kind: kind, requestID: requestID, fields: fields)
  }

  private func finish(_ response: ControllerLinkResponse) async -> ControllerLinkResponse {
    await record(
      kind: "controller.link.response.sent",
      requestID: response.requestID,
      fields: responseFields(response)
    )
    return response
  }

  private func requestFields(_ request: ControllerLinkRequest) -> SimulationDiagnosticFields {
    switch request {
    case .status:
      return ["command": .text("status")]
    case .pair:
      // Short-lived pairing codes and generated authorizations never enter the record.
      return ["command": .text("pair")]
    case .apply(_, _, let latitude, let longitude):
      return [
        "command": .text("apply"),
        "latitude": .number(latitude),
        "longitude": .number(longitude),
      ]
    case .stop:
      return ["command": .text("stop")]
    }
  }

  private func responseFields(_ response: ControllerLinkResponse) -> SimulationDiagnosticFields {
    switch response {
    case .status(_, let readiness):
      switch readiness {
      case .ready:
        return ["outcome": .text("ready")]
      case .unavailable(let reason):
        return [
          "outcome": .text("unavailable"),
          "reason": .text(reason.rawValue),
        ]
      }
    case .paired:
      return ["outcome": .text("paired")]
    case .applied:
      return ["outcome": .text("applied")]
    case .stopped:
      return ["outcome": .text("stopped")]
    case .failed(_, let reason):
      return [
        "outcome": .text("failed"),
        "reason": .text(reason.rawValue),
      ]
    case .rejected(_, let reason):
      return [
        "outcome": .text("rejected"),
        "reason": .text(reason.rawValue),
      ]
    }
  }

  private func isAuthorized(_ presentedAuthorization: ControllerAuthorization) async -> Bool {
    do {
      guard let storedAuthorization = try await authorizationStore.load() else {
        return false
      }
      return storedAuthorization.securelyMatches(presentedAuthorization)
    } catch {
      return false
    }
  }

  private enum ExpectedCommandResult {
    case status
    case apply
    case stop
  }

  private func processCommand(
    _ command: ControllerCommand,
    expectedResult: ExpectedCommandResult
  ) async -> ControllerLinkResponse {
    let result = await commandHandler.handle(command)
    guard result.requestID == command.requestID else {
      return .failed(
        requestID: command.requestID,
        reason: .responseIdentityMismatch
      )
    }

    switch (expectedResult, result) {
    case (.status, .ready(let requestID)):
      return .status(requestID: requestID, readiness: .ready)
    case (.status, .failed(let requestID, let reason)):
      return .status(
        requestID: requestID,
        readiness: .unavailable(reason)
      )
    case (.apply, .applied(let requestID)):
      return .applied(requestID: requestID)
    case (.stop, .stopped(let requestID)):
      return .stopped(requestID: requestID)
    case (.apply, .failed(let requestID, let reason)),
      (.stop, .failed(let requestID, let reason)):
      return .failed(requestID: requestID, reason: reason)
    case (.status, .applied),
      (.status, .stopped),
      (.apply, .ready),
      (.apply, .stopped),
      (.stop, .ready),
      (.stop, .applied):
      return .failed(
        requestID: command.requestID,
        reason: .responseIdentityMismatch
      )
    }
  }

  private func map(_ error: PairingCodeError) -> ControllerLinkRejection {
    switch error {
    case .invalidFormat, .incorrect:
      .invalidPairingCode
    case .identityMismatch:
      .identityMismatch
    case .expired:
      .expiredPairingCode
    case .alreadyUsed:
      .pairingCodeAlreadyUsed
    case .tooManyAttempts:
      .tooManyPairingAttempts
    }
  }
}
