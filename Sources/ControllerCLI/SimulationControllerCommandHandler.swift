import ControllerLink
import Foundation
import LocationDomain
import SimulationController

public struct SimulationControllerCommandHandler: ControllerCommandHandling {
  private let controller: SimulationController

  public init(controller: SimulationController) {
    self.controller = controller
  }

  public func handle(_ command: ControllerCommand) async -> ControllerCommandResult {
    switch command {
    case .status(let requestID):
      switch await controller.status() {
      case .ready, .applied, .stopped:
        return .ready(requestID: requestID)
      case .unavailable(let reason), .failed(_, let reason):
        return .failed(requestID: requestID, reason: map(reason))
      }

    case .apply(let requestID, let latitude, let longitude):
      let location: SelectedLocation
      do {
        location = try SelectedLocation(latitude: latitude, longitude: longitude)
      } catch {
        return .failed(requestID: requestID, reason: .invalidCoordinate)
      }

      switch await controller.apply(location, requestID: requestID) {
      case .applied(let responseID, _):
        return .applied(requestID: responseID)
      case .cleared(let responseID):
        return .failed(requestID: responseID, reason: .backendUnavailable)
      case .failed(let responseID, let reason):
        return .failed(requestID: responseID, reason: map(reason))
      }

    case .stop(let requestID):
      switch await controller.stop(requestID: requestID) {
      case .cleared(let responseID):
        return .stopped(requestID: responseID)
      case .applied(let responseID, _):
        return .failed(requestID: responseID, reason: .clearFailed)
      case .failed(let responseID, let reason):
        return .failed(requestID: responseID, reason: map(reason))
      }
    }
  }

  private func map(_ failure: InjectionBackendFailure) -> ControllerCommandFailure {
    switch failure {
    case .noActiveDevice:
      .noActiveDevice
    case .sessionNotReady:
      .sessionNotReady
    case .backendUnavailable:
      .backendUnavailable
    case .timedOut:
      .timedOut
    case .authenticationFailed:
      .authenticationFailed
    case .clearFailed:
      .clearFailed
    }
  }
}
