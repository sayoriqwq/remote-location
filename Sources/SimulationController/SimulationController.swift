import Foundation
import LocationDomain
import SimulationDiagnostics

public enum InjectionBackendFailure: Error, Equatable, Sendable {
  case noActiveDevice
  case sessionNotReady
  case backendUnavailable
  case timedOut
  case authenticationFailed
  case clearFailed
}

public enum InjectionBackendReadiness: Equatable, Sendable {
  case ready
  case unavailable(InjectionBackendFailure)
}

public enum InjectionBackendCommand: Equatable, Sendable {
  case apply(requestID: UUID, location: SelectedLocation)
  case clear(requestID: UUID)
}

public enum InjectionBackendResult: Equatable, Sendable {
  case applied(requestID: UUID, location: SelectedLocation)
  case cleared(requestID: UUID)
  case failed(requestID: UUID, reason: InjectionBackendFailure)
}

public protocol InjectionBackend: Sendable {
  func readiness() async -> InjectionBackendReadiness
  func execute(_ command: InjectionBackendCommand) async -> InjectionBackendResult
}

public enum SimulationControllerStatus: Equatable, Sendable {
  case unavailable(InjectionBackendFailure)
  case ready
  case applied(requestID: UUID, location: SelectedLocation)
  case stopped
  case failed(requestID: UUID, reason: InjectionBackendFailure)
}

public actor SimulationController {
  private let backend: any InjectionBackend
  private let diagnostics: SimulationDiagnosticRecorder?
  private var currentStatus: SimulationControllerStatus = .unavailable(.sessionNotReady)

  public init(
    backend: any InjectionBackend,
    diagnostics: SimulationDiagnosticRecorder? = nil
  ) {
    self.backend = backend
    self.diagnostics = diagnostics
  }

  public func status() async -> SimulationControllerStatus {
    await record(kind: "controller.status.requested")
    if case .unavailable(.sessionNotReady) = currentStatus {
      switch await backend.readiness() {
      case .ready:
        currentStatus = .ready
      case .unavailable(let reason):
        currentStatus = .unavailable(reason)
      }
    }
    await record(
      kind: "controller.status.result",
      fields: statusFields(currentStatus)
    )
    return currentStatus
  }

  public func apply(
    _ location: SelectedLocation,
    requestID: UUID = UUID()
  ) async -> InjectionBackendResult {
    await record(
      kind: "controller.apply.started",
      requestID: requestID,
      fields: coordinateFields(location)
    )
    switch await backend.readiness() {
    case .unavailable(let reason):
      currentStatus = .failed(requestID: requestID, reason: reason)
      let result = InjectionBackendResult.failed(requestID: requestID, reason: reason)
      await recordResult(result, kind: "controller.apply.backend-response")
      return result
    case .ready:
      break
    }

    let result = await backend.execute(.apply(requestID: requestID, location: location))
    switch result {
    case .applied(let responseID, let appliedLocation):
      currentStatus = .applied(requestID: responseID, location: appliedLocation)
    case .cleared(let responseID):
      currentStatus = .failed(requestID: responseID, reason: .backendUnavailable)
    case .failed(let responseID, let reason):
      currentStatus = .failed(requestID: responseID, reason: reason)
    }
    await recordResult(result, kind: "controller.apply.backend-response")
    return result
  }

  public func stop(requestID: UUID = UUID()) async -> InjectionBackendResult {
    await record(kind: "controller.stop.started", requestID: requestID)
    let result = await backend.execute(.clear(requestID: requestID))
    switch result {
    case .cleared:
      currentStatus = .stopped
    case .applied(let responseID, _):
      currentStatus = .failed(requestID: responseID, reason: .clearFailed)
    case .failed(let responseID, let reason):
      currentStatus = .failed(requestID: responseID, reason: reason)
    }
    await recordResult(result, kind: "controller.stop.backend-response")
    return result
  }

  private func record(
    kind: String,
    requestID: UUID? = nil,
    fields: SimulationDiagnosticFields = [:]
  ) async {
    guard let diagnostics else { return }
    await diagnostics.record(kind: kind, requestID: requestID, fields: fields)
  }

  private func recordResult(
    _ result: InjectionBackendResult,
    kind: String
  ) async {
    var fields: SimulationDiagnosticFields = [:]
    switch result {
    case .applied(_, let location):
      fields["outcome"] = .text("applied")
      fields.merge(coordinateFields(location)) { _, new in new }
    case .cleared:
      fields["outcome"] = .text("cleared")
    case .failed(_, let reason):
      fields["outcome"] = .text("failed")
      fields["reason"] = .text(String(describing: reason))
    }
    await record(kind: kind, requestID: result.requestID, fields: fields)
  }

  private func coordinateFields(_ location: SelectedLocation) -> SimulationDiagnosticFields {
    [
      "latitude": .number(location.latitude),
      "longitude": .number(location.longitude),
    ]
  }

  private func statusFields(_ status: SimulationControllerStatus) -> SimulationDiagnosticFields {
    switch status {
    case .unavailable(let reason):
      return [
        "state": .text("unavailable"),
        "reason": .text(String(describing: reason)),
      ]
    case .ready:
      return ["state": .text("ready")]
    case .applied(_, let location):
      var fields = ["state": SimulationDiagnosticValue.text("applied")]
      fields.merge(coordinateFields(location)) { _, new in new }
      return fields
    case .stopped:
      return ["state": .text("stopped")]
    case .failed(_, let reason):
      return [
        "state": .text("failed"),
        "reason": .text(String(describing: reason)),
      ]
    }
  }
}

private extension InjectionBackendResult {
  var requestID: UUID {
    switch self {
    case .applied(let requestID, _), .cleared(let requestID), .failed(let requestID, _):
      requestID
    }
  }
}

public actor InMemoryInjectionBackend: InjectionBackend {
  private var currentReadiness: InjectionBackendReadiness
  private var appliedLocation: SelectedLocation?

  public init(readiness: InjectionBackendReadiness = .ready) {
    currentReadiness = readiness
  }

  public func readiness() -> InjectionBackendReadiness {
    currentReadiness
  }

  public func execute(_ command: InjectionBackendCommand) -> InjectionBackendResult {
    switch currentReadiness {
    case .unavailable(let reason):
      return .failed(requestID: command.requestID, reason: reason)
    case .ready:
      break
    }

    switch command {
    case .apply(let requestID, let location):
      appliedLocation = location
      return .applied(requestID: requestID, location: location)
    case .clear(let requestID):
      appliedLocation = nil
      return .cleared(requestID: requestID)
    }
  }
}

public struct UnavailableInjectionBackend: InjectionBackend {
  private let reason: InjectionBackendFailure

  public init(reason: InjectionBackendFailure) {
    self.reason = reason
  }

  public func readiness() -> InjectionBackendReadiness {
    .unavailable(reason)
  }

  public func execute(_ command: InjectionBackendCommand) -> InjectionBackendResult {
    .failed(requestID: command.requestID, reason: reason)
  }
}

extension InjectionBackendCommand {
  fileprivate var requestID: UUID {
    switch self {
    case .apply(let requestID, _), .clear(let requestID):
      requestID
    }
  }
}
