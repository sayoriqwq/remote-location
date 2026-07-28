import XCTest

@testable import ControllerLink

final class PairingCodeAuthorityTests: XCTestCase {
  func testCorrectCodePairsThePresentedIdentityOnlyOnce() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0xA1, count: 32))
    let authority = try PairingCodeAuthority(
      code: "123456",
      identity: identity,
      expiresAt: Date(timeIntervalSince1970: 200)
    )

    let firstResult = try await authority.redeem(
      code: "123456",
      presentedIdentity: identity,
      at: Date(timeIntervalSince1970: 100)
    )

    XCTAssertEqual(firstResult, .paired(identity))
    await XCTAssertThrowsErrorAsync(
      try await authority.redeem(
        code: "123456",
        presentedIdentity: identity,
        at: Date(timeIntervalSince1970: 101)
      )
    ) { error in
      XCTAssertEqual(error as? PairingCodeError, .alreadyUsed)
    }
  }

  func testWrongCodeAndIdentityConsumeTheBoundedAttemptBudget() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0xA1, count: 32))
    let otherIdentity = try ControllerIdentity(fingerprint: Data(repeating: 0xB2, count: 32))
    let authority = try PairingCodeAuthority(
      code: "123456",
      identity: identity,
      expiresAt: Date(timeIntervalSince1970: 200),
      maximumFailedAttempts: 2
    )

    await XCTAssertThrowsErrorAsync(
      try await authority.redeem(
        code: "654321",
        presentedIdentity: identity,
        at: Date(timeIntervalSince1970: 100)
      )
    ) { error in
      XCTAssertEqual(error as? PairingCodeError, .incorrect)
    }
    await XCTAssertThrowsErrorAsync(
      try await authority.redeem(
        code: "123456",
        presentedIdentity: otherIdentity,
        at: Date(timeIntervalSince1970: 101)
      )
    ) { error in
      XCTAssertEqual(error as? PairingCodeError, .identityMismatch)
    }
    await XCTAssertThrowsErrorAsync(
      try await authority.redeem(
        code: "123456",
        presentedIdentity: identity,
        at: Date(timeIntervalSince1970: 102)
      )
    ) { error in
      XCTAssertEqual(error as? PairingCodeError, .tooManyAttempts)
    }
  }

  func testExpiredCodeIsRejectedWithoutPairing() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0xA1, count: 32))
    let authority = try PairingCodeAuthority(
      code: "123456",
      identity: identity,
      expiresAt: Date(timeIntervalSince1970: 100)
    )

    await XCTAssertThrowsErrorAsync(
      try await authority.redeem(
        code: "123456",
        presentedIdentity: identity,
        at: Date(timeIntervalSince1970: 101)
      )
    ) { error in
      XCTAssertEqual(error as? PairingCodeError, .expired)
    }
  }
}

private func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw.", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
