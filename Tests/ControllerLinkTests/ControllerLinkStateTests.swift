import XCTest

@testable import ControllerLink

final class ControllerLinkStateTests: XCTestCase {
  func testDiscoveryPairingConnectionAndDisconnectRemainDistinct() throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x31, count: 32))
    var link = ControllerLinkStateMachine()

    link.discovered(identity, trust: .pairingRequired)
    XCTAssertEqual(link.state, .awaitingPairing(identity))

    link.pairingSucceeded(identity)
    XCTAssertEqual(link.state, .connected(identity))

    link.disconnected()
    XCTAssertEqual(link.state, .unavailable(.disconnected))

    link.localNetworkPermissionDenied()
    XCTAssertEqual(link.state, .localNetworkDenied)
  }
}
