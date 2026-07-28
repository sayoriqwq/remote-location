import ControllerLink
import LocationDomain
import SimulationController
import XCTest

@testable import ControllerCLI

final class SimulationControllerCommandHandlerTests: XCTestCase {
  func testMapsAuthorizedLinkCommandsToTheExistingSimulationController() async throws {
    let controller = SimulationController(backend: InMemoryInjectionBackend())
    let handler = SimulationControllerCommandHandler(controller: controller)

    let applyID = UUID()
    let applied = await handler.handle(
      .apply(
        requestID: applyID,
        latitude: 31.2304,
        longitude: 121.4737
      )
    )
    XCTAssertEqual(applied, .applied(requestID: applyID))

    let stopID = UUID()
    let stopped = await handler.handle(.stop(requestID: stopID))
    XCTAssertEqual(stopped, .stopped(requestID: stopID))
  }

  func testRejectsInvalidCoordinatesBeforeCallingTheInjectionBackend() async {
    let controller = SimulationController(backend: InMemoryInjectionBackend())
    let handler = SimulationControllerCommandHandler(controller: controller)
    let requestID = UUID()

    let result = await handler.handle(
      .apply(requestID: requestID, latitude: 91, longitude: 0)
    )

    XCTAssertEqual(
      result,
      .failed(requestID: requestID, reason: .invalidCoordinate)
    )
    let status = await controller.status()
    XCTAssertEqual(status, .ready)
  }
}
