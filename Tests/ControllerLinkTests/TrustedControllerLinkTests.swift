import XCTest

@testable import ControllerLink

final class TrustedControllerLinkTests: XCTestCase {
  func testPairsOnceThenReusesThePinnedControllerIdentity() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x19, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x31, count: 32))
    let store = InMemoryControllerTrustStore()
    let authorizationStore = InMemoryControllerAuthorizationStore()
    let trust = ControllerTrust(store: store)
    let firstTransport = PairingTransport(identity: identity, authorization: authorization)
    let service = ControllerService(name: "controller")
    let firstLink = TrustedControllerLink(
      trust: trust,
      authorizationStore: authorizationStore,
      transport: firstTransport
    )

    let awaitingPairing = await firstLink.connect(to: service)
    XCTAssertEqual(awaitingPairing, .awaitingPairing(identity))
    let paired = await firstLink.pair(code: "123456")
    XCTAssertEqual(paired, .connected(identity))
    let storedIdentity = await store.load()
    XCTAssertEqual(storedIdentity, identity)
    let storedAuthorization = await authorizationStore.load()
    XCTAssertEqual(storedAuthorization, authorization)

    let reconnectTransport = TrustedStatusTransport(
      identity: identity,
      authorization: authorization
    )
    let reconnect = TrustedControllerLink(
      trust: trust,
      authorizationStore: authorizationStore,
      transport: reconnectTransport
    )
    let reconnected = await reconnect.connect(to: service)
    XCTAssertEqual(reconnected, .connected(identity))
    let expectedIdentity = await reconnectTransport.lastExpectedIdentity()
    XCTAssertEqual(expectedIdentity, identity)
  }

  func testMismatchedResponseIdentityNeverBecomesTrusted() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x27, count: 32))
    let store = InMemoryControllerTrustStore()
    let link = TrustedControllerLink(
      trust: ControllerTrust(store: store),
      authorizationStore: InMemoryControllerAuthorizationStore(),
      transport: MismatchedResponseTransport(identity: identity)
    )

    _ = await link.connect(to: ControllerService(name: "controller"))
    let pairingResult = await link.pair(code: "123456")
    XCTAssertEqual(pairingResult, .unavailable(.transportUnavailable))
    let storedIdentity = await store.load()
    XCTAssertNil(storedIdentity)
  }

  func testConnectedLinkSendsAuthorizedCorrelatedApplyAndStop() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x71, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x72, count: 32))
    let transport = AuthorizedCommandTransport(
      identity: identity,
      authorization: authorization
    )
    let link = TrustedControllerLink(
      trust: ControllerTrust(store: InMemoryControllerTrustStore(identity: identity)),
      authorizationStore: InMemoryControllerAuthorizationStore(
        authorization: authorization
      ),
      transport: transport
    )
    let connected = await link.connect(to: ControllerService(name: "controller"))
    XCTAssertEqual(connected, .connected(identity))
    let readiness = await link.currentBackendReadiness()
    XCTAssertEqual(readiness, .ready)

    let applyID = UUID()
    let applied = await link.apply(
      requestID: applyID,
      latitude: 31.2304,
      longitude: 121.4737
    )
    XCTAssertEqual(applied, .applied(requestID: applyID))
    let stopID = UUID()
    let stopped = await link.stop(requestID: stopID)
    XCTAssertEqual(stopped, .stopped(requestID: stopID))
  }

  func testApplyAndStopRefreshTheTrustedLinkAfterTransientDiscoveryLoss() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x75, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x76, count: 32))
    let transport = AuthorizedCommandTransport(
      identity: identity,
      authorization: authorization
    )
    let link = TrustedControllerLink(
      trust: ControllerTrust(store: InMemoryControllerTrustStore(identity: identity)),
      authorizationStore: InMemoryControllerAuthorizationStore(
        authorization: authorization
      ),
      transport: transport
    )

    let connected = await link.connect(to: ControllerService(name: "controller"))
    XCTAssertEqual(connected, .connected(identity))
    _ = await link.disconnected()

    let requestID = UUID()
    let response = await link.apply(
      requestID: requestID,
      latitude: 31.2304,
      longitude: 121.4737
    )

    XCTAssertEqual(response, .applied(requestID: requestID))
    let refreshedState = await link.currentState()
    XCTAssertEqual(refreshedState, .connected(identity))

    _ = await link.disconnected()
    let stopID = UUID()
    let stopResponse = await link.stop(requestID: stopID)

    XCTAssertEqual(stopResponse, .stopped(requestID: stopID))
    let stopRefreshedState = await link.currentState()
    XCTAssertEqual(stopRefreshedState, .connected(identity))
  }

  func testUnavailableBackendPreventsApplyWithoutSendingACommand() async throws {
    let identity = try ControllerIdentity(fingerprint: Data(repeating: 0x73, count: 32))
    let authorization = try ControllerAuthorization(bytes: Data(repeating: 0x74, count: 32))
    let transport = UnavailableBackendTransport(
      identity: identity,
      authorization: authorization
    )
    let link = TrustedControllerLink(
      trust: ControllerTrust(store: InMemoryControllerTrustStore(identity: identity)),
      authorizationStore: InMemoryControllerAuthorizationStore(
        authorization: authorization
      ),
      transport: transport
    )
    let state = await link.connect(to: ControllerService(name: "controller"))
    XCTAssertEqual(state, .connected(identity))

    let requestID = UUID()
    let response = await link.apply(
      requestID: requestID,
      latitude: 31.2304,
      longitude: 121.4737
    )

    XCTAssertEqual(
      response,
      .failed(requestID: requestID, reason: .sessionNotReady)
    )
    let applyCount = await transport.applyCount()
    XCTAssertEqual(applyCount, 0)
  }
}

private actor PairingTransport: ControllerLinkTransport {
  let identity: ControllerIdentity
  let authorization: ControllerAuthorization

  init(identity: ControllerIdentity, authorization: ControllerAuthorization) {
    self.identity = identity
    self.authorization = authorization
  }

  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) throws -> ControllerTransportReply {
    switch request {
    case .status(let requestID, let presentedAuthorization):
      XCTAssertNil(presentedAuthorization)
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .rejected(requestID: requestID, reason: .pairingRequired)
      )
    case .pair(let requestID, let code):
      XCTAssertEqual(code, "123456")
      XCTAssertEqual(expectedIdentity, identity)
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .paired(requestID: requestID, authorization: authorization)
      )
    case .apply, .stop:
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .rejected(requestID: request.requestID, reason: .invalidRequest)
      )
    }
  }
}

private actor TrustedStatusTransport: ControllerLinkTransport {
  let identity: ControllerIdentity
  let authorization: ControllerAuthorization
  private var expectedIdentity: ControllerIdentity?

  init(identity: ControllerIdentity, authorization: ControllerAuthorization) {
    self.identity = identity
    self.authorization = authorization
  }

  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) throws -> ControllerTransportReply {
    self.expectedIdentity = expectedIdentity
    guard case .status(let requestID, let presentedAuthorization) = request else {
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .rejected(requestID: request.requestID, reason: .invalidRequest)
      )
    }
    XCTAssertEqual(presentedAuthorization, authorization)
    return ControllerTransportReply(
      presentedIdentity: identity,
      response: .status(requestID: requestID, readiness: .ready)
    )
  }

  func lastExpectedIdentity() -> ControllerIdentity? {
    expectedIdentity
  }
}

private actor MismatchedResponseTransport: ControllerLinkTransport {
  let identity: ControllerIdentity

  init(identity: ControllerIdentity) {
    self.identity = identity
  }

  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) throws -> ControllerTransportReply {
    switch request {
    case .status(let requestID, _):
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .rejected(requestID: requestID, reason: .pairingRequired)
      )
    case .pair:
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .paired(
          requestID: UUID(),
          authorization: try ControllerAuthorization(bytes: Data(repeating: 0x55, count: 32))
        )
      )
    case .apply, .stop:
      return ControllerTransportReply(
        presentedIdentity: identity,
        response: .rejected(requestID: request.requestID, reason: .invalidRequest)
      )
    }
  }
}

private actor AuthorizedCommandTransport: ControllerLinkTransport {
  let identity: ControllerIdentity
  let authorization: ControllerAuthorization

  init(identity: ControllerIdentity, authorization: ControllerAuthorization) {
    self.identity = identity
    self.authorization = authorization
  }

  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) throws -> ControllerTransportReply {
    XCTAssertEqual(expectedIdentity, identity)
    let response: ControllerLinkResponse
    switch request {
    case .status(let requestID, let presentedAuthorization):
      XCTAssertEqual(presentedAuthorization, authorization)
      response = .status(requestID: requestID, readiness: .ready)
    case .apply(let requestID, let presentedAuthorization, let latitude, let longitude):
      XCTAssertEqual(presentedAuthorization, authorization)
      XCTAssertEqual(latitude, 31.2304)
      XCTAssertEqual(longitude, 121.4737)
      response = .applied(requestID: requestID)
    case .stop(let requestID, let presentedAuthorization):
      XCTAssertEqual(presentedAuthorization, authorization)
      response = .stopped(requestID: requestID)
    case .pair(let requestID, _):
      response = .rejected(requestID: requestID, reason: .invalidRequest)
    }
    return ControllerTransportReply(presentedIdentity: identity, response: response)
  }
}

private actor UnavailableBackendTransport: ControllerLinkTransport {
  let identity: ControllerIdentity
  let authorization: ControllerAuthorization
  private var sentApplyCount = 0

  init(identity: ControllerIdentity, authorization: ControllerAuthorization) {
    self.identity = identity
    self.authorization = authorization
  }

  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) -> ControllerTransportReply {
    let response: ControllerLinkResponse
    switch request {
    case .status(let requestID, let presentedAuthorization):
      XCTAssertEqual(presentedAuthorization, authorization)
      response = .status(
        requestID: requestID,
        readiness: .unavailable(.sessionNotReady)
      )
    case .apply(let requestID, _, _, _):
      sentApplyCount += 1
      response = .applied(requestID: requestID)
    case .pair(let requestID, _), .stop(let requestID, _):
      response = .rejected(requestID: requestID, reason: .invalidRequest)
    }
    return ControllerTransportReply(presentedIdentity: identity, response: response)
  }

  func applyCount() -> Int {
    sentApplyCount
  }
}
