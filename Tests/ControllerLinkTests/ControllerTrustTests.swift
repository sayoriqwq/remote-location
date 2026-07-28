import XCTest

@testable import ControllerLink

final class ControllerTrustTests: XCTestCase {
  func testControllerIdentityUsesTheLeafCertificateSHA256Fingerprint() throws {
    let identity = try ControllerIdentity(certificateDER: Data("abc".utf8))

    XCTAssertEqual(
      identity.fingerprint,
      Data([
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
      ])
    )
  }

  func testRememberedIdentityIsReusedAndDifferentIdentityIsRejected() async throws {
    let trusted = try ControllerIdentity(fingerprint: Data(repeating: 0x11, count: 32))
    let different = try ControllerIdentity(fingerprint: Data(repeating: 0x22, count: 32))
    let trust = ControllerTrust(store: InMemoryControllerTrustStore())

    let initial = try await trust.evaluate(trusted)
    XCTAssertEqual(initial, .pairingRequired)

    try await trust.remember(trusted)

    let reused = try await trust.evaluate(trusted)
    XCTAssertEqual(reused, .trusted)
    let mismatch = try await trust.evaluate(different)
    XCTAssertEqual(mismatch, .identityMismatch)
  }
}
