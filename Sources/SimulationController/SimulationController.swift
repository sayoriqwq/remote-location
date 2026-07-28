import Foundation
import LocationDomain

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
  private var currentStatus: SimulationControllerStatus = .unavailable(.sessionNotReady)

  public init(backend: any InjectionBackend) {
    self.backend = backend
  }

  public func status() async -> SimulationControllerStatus {
    if case .unavailable(.sessionNotReady) = currentStatus {
      switch await backend.readiness() {
      case .ready:
        currentStatus = .ready
      case .unavailable(let reason):
        currentStatus = .unavailable(reason)
      }
    }
    return currentStatus
  }

  public func apply(
    _ location: SelectedLocation,
    requestID: UUID = UUID()
  ) async -> InjectionBackendResult {
    switch await backend.readiness() {
    case .unavailable(let reason):
      currentStatus = .failed(requestID: requestID, reason: reason)
      return .failed(requestID: requestID, reason: reason)
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
    return result
  }

  public func stop(requestID: UUID = UUID()) async -> InjectionBackendResult {
    let result = await backend.execute(.clear(requestID: requestID))
    switch result {
    case .cleared:
      currentStatus = .stopped
    case .applied(let responseID, _):
      currentStatus = .failed(requestID: responseID, reason: .clearFailed)
    case .failed(let responseID, let reason):
      currentStatus = .failed(requestID: responseID, reason: reason)
    }
    return result
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
