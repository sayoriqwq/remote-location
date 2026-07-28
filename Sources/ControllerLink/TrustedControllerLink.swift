import Foundation

public struct ControllerService: Codable, Hashable, Sendable {
  public static let serviceType = "_remote-location._tcp"

  public let name: String
  public let type: String
  public let domain: String?

  public init(
    name: String,
    type: String = ControllerService.serviceType,
    domain: String? = nil
  ) {
    self.name = name
    self.type = type
    self.domain = domain
  }
}

public enum ControllerLinkRequest: Codable, Equatable, Sendable {
  case status(requestID: UUID, authorization: ControllerAuthorization?)
  case pair(requestID: UUID, code: String)
  case apply(
    requestID: UUID,
    authorization: ControllerAuthorization,
    latitude: Double,
    longitude: Double
  )
  case stop(requestID: UUID, authorization: ControllerAuthorization)

  public var requestID: UUID {
    switch self {
    case .status(let requestID, _),
      .pair(let requestID, _),
      .apply(let requestID, _, _, _),
      .stop(let requestID, _):
      requestID
    }
  }
}

public enum ControllerLinkRejection: String, Codable, Error, Equatable, Sendable {
  case pairingRequired
  case invalidPairingCode
  case expiredPairingCode
  case pairingCodeAlreadyUsed
  case tooManyPairingAttempts
  case identityMismatch
  case authorizationFailed
  case invalidRequest
}

public enum ControllerLinkResponse: Codable, Equatable, Sendable {
  case status(requestID: UUID, readiness: ControllerBackendReadiness)
  case paired(requestID: UUID, authorization: ControllerAuthorization)
  case applied(requestID: UUID)
  case stopped(requestID: UUID)
  case failed(requestID: UUID, reason: ControllerCommandFailure)
  case rejected(requestID: UUID, reason: ControllerLinkRejection)

  public var requestID: UUID {
    switch self {
    case .status(let requestID, _),
      .paired(let requestID, _),
      .applied(let requestID),
      .stopped(let requestID),
      .failed(let requestID, _),
      .rejected(let requestID, _):
      requestID
    }
  }
}

public struct ControllerTransportReply: Equatable, Sendable {
  public let presentedIdentity: ControllerIdentity
  public let response: ControllerLinkResponse

  public init(
    presentedIdentity: ControllerIdentity,
    response: ControllerLinkResponse
  ) {
    self.presentedIdentity = presentedIdentity
    self.response = response
  }
}

public protocol ControllerLinkTransport: Sendable {
  func send(
    _ request: ControllerLinkRequest,
    to service: ControllerService,
    expectedIdentity: ControllerIdentity?
  ) async throws -> ControllerTransportReply
}

public actor TrustedControllerLink {
  private let trust: ControllerTrust
  private let authorizationStore: any ControllerAuthorizationStore
  private let transport: any ControllerLinkTransport
  private var stateMachine = ControllerLinkStateMachine()
  private var currentService: ControllerService?
  private var pendingIdentity: ControllerIdentity?
  private var backendReadiness: ControllerBackendReadiness?

  public init(
    trust: ControllerTrust,
    authorizationStore: any ControllerAuthorizationStore,
    transport: any ControllerLinkTransport
  ) {
    self.trust = trust
    self.authorizationStore = authorizationStore
    self.transport = transport
  }

  public func connect(to service: ControllerService) async -> ControllerLinkState {
    currentService = service
    backendReadiness = nil
    let trustedIdentity: ControllerIdentity?
    do {
      trustedIdentity = try await trust.trustedIdentity()
    } catch {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }

    let authorization: ControllerAuthorization?
    do {
      authorization = try await authorizationStore.load()
    } catch {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    let request = ControllerLinkRequest.status(
      requestID: UUID(),
      authorization: authorization
    )
    let reply: ControllerTransportReply
    do {
      reply = try await transport.send(
        request,
        to: service,
        expectedIdentity: trustedIdentity
      )
    } catch {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    guard reply.response.requestID == request.requestID else {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }

    if let trustedIdentity {
      guard reply.presentedIdentity == trustedIdentity else {
        stateMachine.discovered(reply.presentedIdentity, trust: .identityMismatch)
        return stateMachine.state
      }
      if case .rejected(_, .pairingRequired) = reply.response {
        pendingIdentity = trustedIdentity
        stateMachine.discovered(trustedIdentity, trust: .pairingRequired)
        return stateMachine.state
      }
      guard
        case .status(_, let readiness) = reply.response,
        authorization != nil
      else {
        stateMachine.transportUnavailable()
        return stateMachine.state
      }
      backendReadiness = readiness
      pendingIdentity = nil
      stateMachine.discovered(trustedIdentity, trust: .trusted)
      return stateMachine.state
    }

    guard case .rejected(_, .pairingRequired) = reply.response else {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    pendingIdentity = reply.presentedIdentity
    stateMachine.discovered(reply.presentedIdentity, trust: .pairingRequired)
    return stateMachine.state
  }

  public func pair(code: String) async -> ControllerLinkState {
    guard let service = currentService, let identity = pendingIdentity else {
      stateMachine.pairingFailed()
      return stateMachine.state
    }

    let request = ControllerLinkRequest.pair(requestID: UUID(), code: code)
    let reply: ControllerTransportReply
    do {
      reply = try await transport.send(
        request,
        to: service,
        expectedIdentity: identity
      )
    } catch {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    guard
      reply.presentedIdentity == identity,
      reply.response.requestID == request.requestID
    else {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }

    guard case .paired(_, let authorization) = reply.response else {
      stateMachine.pairingFailed()
      return stateMachine.state
    }
    do {
      try await authorizationStore.save(authorization)
      try await trust.remember(identity)
    } catch {
      try? await authorizationStore.remove()
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    pendingIdentity = nil
    stateMachine.pairingSucceeded(identity)
    return stateMachine.state
  }

  public func apply(
    requestID: UUID,
    latitude: Double,
    longitude: Double
  ) async -> ControllerLinkResponse {
    let needsRefresh: Bool
    if case .connected = stateMachine.state {
      needsRefresh = backendReadiness == nil
    } else {
      needsRefresh = true
    }
    if needsRefresh {
      _ = await refresh()
    }

    switch backendReadiness {
    case .ready:
      break
    case .unavailable(let reason):
      return .failed(requestID: requestID, reason: reason)
    case nil:
      return .failed(requestID: requestID, reason: .controllerUnavailable)
    }
    return await sendAuthorized(
      requestID: requestID,
      makeRequest: { authorization in
        .apply(
          requestID: requestID,
          authorization: authorization,
          latitude: latitude,
          longitude: longitude
        )
      },
      accepts: { response in
        if case .applied = response { return true }
        return false
      }
    )
  }

  public func stop(requestID: UUID) async -> ControllerLinkResponse {
    switch stateMachine.state {
    case .connected:
      break
    default:
      _ = await refresh()
    }

    return await sendAuthorized(
      requestID: requestID,
      makeRequest: { authorization in
        .stop(requestID: requestID, authorization: authorization)
      },
      accepts: { response in
        if case .stopped = response { return true }
        return false
      }
    )
  }

  public func currentState() -> ControllerLinkState {
    stateMachine.state
  }

  public func currentBackendReadiness() -> ControllerBackendReadiness? {
    backendReadiness
  }

  public func refresh() async -> ControllerLinkState {
    guard let currentService else {
      stateMachine.transportUnavailable()
      backendReadiness = nil
      return stateMachine.state
    }
    return await connect(to: currentService)
  }

  public func forgetController() async -> ControllerLinkState {
    do {
      try await trust.forget()
      try await authorizationStore.remove()
    } catch {
      stateMachine.transportUnavailable()
      return stateMachine.state
    }
    currentService = nil
    pendingIdentity = nil
    backendReadiness = nil
    stateMachine.resetDiscovery()
    return stateMachine.state
  }

  public func disconnected() -> ControllerLinkState {
    stateMachine.disconnected()
    backendReadiness = nil
    return stateMachine.state
  }

  public func localNetworkPermissionDenied() -> ControllerLinkState {
    stateMachine.localNetworkPermissionDenied()
    backendReadiness = nil
    return stateMachine.state
  }

  private func sendAuthorized(
    requestID: UUID,
    makeRequest: (ControllerAuthorization) -> ControllerLinkRequest,
    accepts: (ControllerLinkResponse) -> Bool
  ) async -> ControllerLinkResponse {
    guard
      let service = currentService,
      case .connected(let identity) = stateMachine.state
    else {
      return .failed(requestID: requestID, reason: .controllerUnavailable)
    }

    let authorization: ControllerAuthorization
    do {
      guard let storedAuthorization = try await authorizationStore.load() else {
        stateMachine.transportUnavailable()
        return .failed(requestID: requestID, reason: .controllerUnavailable)
      }
      authorization = storedAuthorization
    } catch {
      stateMachine.transportUnavailable()
      return .failed(requestID: requestID, reason: .controllerUnavailable)
    }

    let request = makeRequest(authorization)
    let reply: ControllerTransportReply
    do {
      reply = try await transport.send(
        request,
        to: service,
        expectedIdentity: identity
      )
    } catch {
      stateMachine.transportUnavailable()
      return .failed(requestID: requestID, reason: .controllerUnavailable)
    }

    guard reply.presentedIdentity == identity else {
      stateMachine.discovered(reply.presentedIdentity, trust: .identityMismatch)
      return .failed(requestID: requestID, reason: .responseIdentityMismatch)
    }
    guard reply.response.requestID == requestID else {
      stateMachine.transportUnavailable()
      return .failed(requestID: requestID, reason: .responseIdentityMismatch)
    }
    if accepts(reply.response) {
      return reply.response
    }
    switch reply.response {
    case .failed, .rejected:
      return reply.response
    case .status, .paired, .applied, .stopped:
      stateMachine.transportUnavailable()
      return .failed(requestID: requestID, reason: .responseIdentityMismatch)
    }
  }
}
