import XCTest

@testable import ControllerLink

final class ControllerServerSessionTests: XCTestCase {
  func testCorrectCodePairsWhenServerPersistsAuthorizationInKeychain() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x35, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x53, count: 32))
    let store = KeychainControllerAuthorizationStore(
      service: "dev.sayori.remotelocation.tests.\(UUID().uuidString)",
      account: "paired-learning-app"
    )
    let session = ControllerServerSession(
      identity: identity,
      pairingAuthority: try PairingCodeAuthority(
        code: "123456",
        identity: identity,
        expiresAt: Date(timeIntervalSince1970: 200)
      ),
      authorizationStore: store,
      now: { Date(timeIntervalSince1970: 100) },
      makeAuthorization: { authorization }
    )

    let requestID = UUID()
    let response = await session.process(.pair(requestID: requestID, code: "123456"))
    try? await store.remove()

    XCTAssertEqual(response, .paired(requestID: requestID, authorization: authorization))
  }

  func testRejectsUnpairedStatusThenPersistsOnePairingAuthorization() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x42, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x24, count: 32))
    let store = InMemoryControllerAuthorizationStore()
    let authority = try PairingCodeAuthority(
      code: "123456",
      identity: identity,
      expiresAt: Date(timeIntervalSince1970: 200)
    )
    let session = ControllerServerSession(
      identity: identity,
      pairingAuthority: authority,
      authorizationStore: store,
      now: { Date(timeIntervalSince1970: 100) },
      makeAuthorization: { authorization }
    )

    let statusID = UUID()
    let unpairedStatus = await session.process(
      .status(requestID: statusID, authorization: nil)
    )
    XCTAssertEqual(unpairedStatus, .rejected(requestID: statusID, reason: .pairingRequired))
    let pairID = UUID()
    let paired = await session.process(.pair(requestID: pairID, code: "123456"))
    XCTAssertEqual(paired, .paired(requestID: pairID, authorization: authorization))
    let trustedStatusID = UUID()
    let trustedStatus = await session.process(
      .status(requestID: trustedStatusID, authorization: authorization)
    )
    XCTAssertEqual(
      trustedStatus,
      .status(
        requestID: trustedStatusID,
        readiness: .unavailable(.backendUnavailable)
      )
    )

    let restarted = ControllerServerSession(
      identity: identity,
      pairingAuthority: try PairingCodeAuthority(
        code: "654321",
        identity: identity,
        expiresAt: Date(timeIntervalSince1970: 300)
      ),
      authorizationStore: store,
      now: { Date(timeIntervalSince1970: 100) },
      makeAuthorization: { authorization }
    )
    let restartStatusID = UUID()
    let restartedStatus = await restarted.process(
      .status(requestID: restartStatusID, authorization: authorization)
    )
    XCTAssertEqual(
      restartedStatus,
      .status(
        requestID: restartStatusID,
        readiness: .unavailable(.backendUnavailable)
      )
    )
  }

  func testAuthorizedApplyAndStopReachHandlerButInvalidAuthorizationDoesNot() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x61, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x62, count: 32))
    let invalidAuthorization = try ControllerAuthorization(bytes: Data(repeating: 0x63, count: 32))
    let store = InMemoryControllerAuthorizationStore(authorization: authorization)
    let handler = RecordingControllerCommandHandler()
    let session = ControllerServerSession(
      identity: identity,
      pairingAuthority: try PairingCodeAuthority(
        code: "123456",
        identity: identity,
        expiresAt: Date(timeIntervalSince1970: 200)
      ),
      authorizationStore: store,
      commandHandler: handler,
      now: { Date(timeIntervalSince1970: 100) }
    )

    let rejectedID = UUID()
    let rejected = await session.process(
      .apply(
        requestID: rejectedID,
        authorization: invalidAuthorization,
        latitude: 31.2304,
        longitude: 121.4737
      )
    )
    XCTAssertEqual(
      rejected,
      .rejected(requestID: rejectedID, reason: .authorizationFailed)
    )
    let commandsAfterRejection = await handler.recordedCommands()
    XCTAssertEqual(commandsAfterRejection, [])

    let applyID = UUID()
    let applied = await session.process(
      .apply(
        requestID: applyID,
        authorization: authorization,
        latitude: 31.2304,
        longitude: 121.4737
      )
    )
    XCTAssertEqual(applied, .applied(requestID: applyID))

    let stopID = UUID()
    let stopped = await session.process(
      .stop(requestID: stopID, authorization: authorization)
    )
    XCTAssertEqual(stopped, .stopped(requestID: stopID))
    let recordedCommands = await handler.recordedCommands()
    XCTAssertEqual(
      recordedCommands,
      [
        .apply(requestID: applyID, latitude: 31.2304, longitude: 121.4737),
        .stop(requestID: stopID),
      ]
    )
  }
}

private actor RecordingControllerCommandHandler: ControllerCommandHandling {
  private var commands: [ControllerCommand] = []

  func handle(_ command: ControllerCommand) -> ControllerCommandResult {
    commands.append(command)
    switch command {
    case .status(let requestID):
      return .ready(requestID: requestID)
    case .apply(let requestID, _, _):
      return .applied(requestID: requestID)
    case .stop(let requestID):
      return .stopped(requestID: requestID)
    }
  }

  func recordedCommands() -> [ControllerCommand] {
    commands
  }
}
