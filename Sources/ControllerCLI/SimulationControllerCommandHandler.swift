import ControllerLink
import Foundation
import LocationDomain
import SimulationDiagnostics
import SimulationController

public struct SimulationControllerCommandHandler: ControllerCommandHandling {
  private let controller: SimulationController
  private let diagnostics: SimulationDiagnosticRecorder?

  public init(
    controller: SimulationController,
    diagnostics: SimulationDiagnosticRecorder? = nil
  ) {
    self.controller = controller
    self.diagnostics = diagnostics
  }

  public func handle(_ command: ControllerCommand) async -> ControllerCommandResult {
    await record(
      kind: "controller.link.command.received",
      requestID: command.requestID,
      fields: commandFields(command)
    )
    let result: ControllerCommandResult
    switch command {
    case .status(let requestID):
      switch await controller.status() {
      case .ready, .applied, .stopped:
        result = .ready(requestID: requestID)
      case .unavailable(let reason), .failed(_, let reason):
        result = .failed(requestID: requestID, reason: map(reason))
      }

    case .apply(let requestID, let latitude, let longitude):
      let location: SelectedLocation
      do {
        location = try SelectedLocation(latitude: latitude, longitude: longitude)
      } catch {
        result = .failed(requestID: requestID, reason: .invalidCoordinate)
        break
      }

      switch await controller.apply(location, requestID: requestID) {
      case .applied(let responseID, _):
        result = .applied(requestID: responseID)
      case .cleared(let responseID):
        result = .failed(requestID: responseID, reason: .backendUnavailable)
      case .failed(let responseID, let reason):
        result = .failed(requestID: responseID, reason: map(reason))
      }

    case .stop(let requestID):
      switch await controller.stop(requestID: requestID) {
      case .cleared(let responseID):
        result = .stopped(requestID: responseID)
      case .applied(let responseID, _):
        result = .failed(requestID: responseID, reason: .clearFailed)
      case .failed(let responseID, let reason):
        result = .failed(requestID: responseID, reason: map(reason))
      }
    }
    await record(
      kind: "controller.link.command.completed",
      requestID: result.requestID,
      fields: resultFields(result)
    )
    return result
  }

  private func record(
    kind: String,
    requestID: UUID,
    fields: SimulationDiagnosticFields
  ) async {
    guard let diagnostics else { return }
    await diagnostics.record(kind: kind, requestID: requestID, fields: fields)
  }

  private func commandFields(_ command: ControllerCommand) -> SimulationDiagnosticFields {
    switch command {
    case .status:
      return ["command": .text("status")]
    case .apply(_, let latitude, let longitude):
      return [
        "command": .text("apply"),
        "latitude": .number(latitude),
        "longitude": .number(longitude),
      ]
    case .stop:
      return ["command": .text("stop")]
    }
  }

  private func resultFields(_ result: ControllerCommandResult) -> SimulationDiagnosticFields {
    switch result {
    case .ready:
      return ["outcome": .text("ready")]
    case .applied:
      return ["outcome": .text("applied")]
    case .stopped:
      return ["outcome": .text("stopped")]
    case .failed(_, let reason):
      return [
        "outcome": .text("failed"),
        "reason": .text(reason.rawValue),
      ]
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
