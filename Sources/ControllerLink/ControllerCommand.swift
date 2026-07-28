import Foundation

public enum ControllerCommand: Equatable, Sendable {
  case status(requestID: UUID)
  case apply(requestID: UUID, latitude: Double, longitude: Double)
  case stop(requestID: UUID)

  public var requestID: UUID {
    switch self {
    case .status(let requestID),
      .apply(let requestID, _, _),
      .stop(let requestID):
      requestID
    }
  }
}

public enum ControllerBackendReadiness: Codable, Equatable, Sendable {
  case ready
  case unavailable(ControllerCommandFailure)
}

public enum ControllerCommandFailure: String, Codable, Error, Equatable, Sendable {
  case invalidCoordinate
  case noActiveDevice
  case sessionNotReady
  case backendUnavailable
  case timedOut
  case authenticationFailed
  case clearFailed
  case controllerUnavailable
  case responseIdentityMismatch
}

public enum ControllerCommandResult: Equatable, Sendable {
  case ready(requestID: UUID)
  case applied(requestID: UUID)
  case stopped(requestID: UUID)
  case failed(requestID: UUID, reason: ControllerCommandFailure)

  public var requestID: UUID {
    switch self {
    case .ready(let requestID),
      .applied(let requestID),
      .stopped(let requestID),
      .failed(let requestID, _):
      requestID
    }
  }
}

public protocol ControllerCommandHandling: Sendable {
  func handle(_ command: ControllerCommand) async -> ControllerCommandResult
}

public struct UnavailableControllerCommandHandler: ControllerCommandHandling {
  public init() {}

  public func handle(_ command: ControllerCommand) -> ControllerCommandResult {
    .failed(requestID: command.requestID, reason: .backendUnavailable)
  }
}
