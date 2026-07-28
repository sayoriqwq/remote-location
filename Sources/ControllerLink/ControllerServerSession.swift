import Foundation

public actor ControllerServerSession {
  private let identity: ControllerIdentity
  private let pairingAuthority: PairingCodeAuthority
  private let authorizationStore: any ControllerAuthorizationStore
  private let commandHandler: any ControllerCommandHandling
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
    }
  ) {
    self.identity = identity
    self.pairingAuthority = pairingAuthority
    self.authorizationStore = authorizationStore
    self.commandHandler = commandHandler
    self.now = now
    self.makeAuthorization = makeAuthorization
  }

  public func process(_ request: ControllerLinkRequest) async -> ControllerLinkResponse {
    switch request {
    case .status(let requestID, let presentedAuthorization):
      guard
        let presentedAuthorization,
        await isAuthorized(presentedAuthorization)
      else {
        return .rejected(requestID: requestID, reason: .pairingRequired)
      }
      return await processCommand(
        .status(requestID: requestID),
        expectedResult: .status
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
        return .paired(requestID: requestID, authorization: authorization)
      } catch let error as PairingCodeError {
        return .rejected(requestID: requestID, reason: map(error))
      } catch {
        return .rejected(requestID: requestID, reason: .invalidRequest)
      }

    case .apply(
      let requestID,
      let presentedAuthorization,
      let latitude,
      let longitude
    ):
      guard await isAuthorized(presentedAuthorization) else {
        return .rejected(requestID: requestID, reason: .authorizationFailed)
      }
      guard
        latitude.isFinite,
        longitude.isFinite,
        (-90.0...90.0).contains(latitude),
        (-180.0...180.0).contains(longitude)
      else {
        return .failed(requestID: requestID, reason: .invalidCoordinate)
      }
      return await processCommand(
        .apply(
          requestID: requestID,
          latitude: latitude,
          longitude: longitude
        ),
        expectedResult: .apply
      )

    case .stop(let requestID, let presentedAuthorization):
      guard await isAuthorized(presentedAuthorization) else {
        return .rejected(requestID: requestID, reason: .authorizationFailed)
      }
      return await processCommand(
        .stop(requestID: requestID),
        expectedResult: .stop
      )
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
