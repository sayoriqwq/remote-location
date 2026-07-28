import LocationDomain
import XCTest

@testable import SimulationController

final class SimulationControllerTests: XCTestCase {
  func testReadyBackendAppliesCoordinateAndReportsAppliedState() async throws {
    let backend = InMemoryInjectionBackend(readiness: .ready)
    let controller = SimulationController(backend: backend)
    let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let location = try SelectedLocation(latitude: 31.2304, longitude: 121.4737)

    let result = await controller.apply(location, requestID: requestID)

    XCTAssertEqual(result, .applied(requestID: requestID, location: location))
    let status = await controller.status()
    XCTAssertEqual(status, .applied(requestID: requestID, location: location))
  }
}
