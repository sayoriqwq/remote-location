public enum ControllerLinkFailure: Equatable, Sendable {
  case disconnected
  case tlsIdentityMismatch
  case pairingFailed
  case transportUnavailable
}

public enum ControllerLinkState: Equatable, Sendable {
  case notDiscovered
  case awaitingPairing(ControllerIdentity)
  case connected(ControllerIdentity)
  case unavailable(ControllerLinkFailure)
  case localNetworkDenied
}

public struct ControllerLinkStateMachine: Equatable, Sendable {
  public private(set) var state: ControllerLinkState = .notDiscovered

  public init() {}

  public mutating func discovered(
    _ identity: ControllerIdentity,
    trust: ControllerTrustDisposition
  ) {
    switch trust {
    case .pairingRequired:
      state = .awaitingPairing(identity)
    case .trusted:
      state = .connected(identity)
    case .identityMismatch:
      state = .unavailable(.tlsIdentityMismatch)
    }
  }

  public mutating func pairingSucceeded(_ identity: ControllerIdentity) {
    state = .connected(identity)
  }

  public mutating func pairingFailed() {
    state = .unavailable(.pairingFailed)
  }

  public mutating func disconnected() {
    state = .unavailable(.disconnected)
  }

  public mutating func transportUnavailable() {
    state = .unavailable(.transportUnavailable)
  }

  public mutating func localNetworkPermissionDenied() {
    state = .localNetworkDenied
  }

  public mutating func resetDiscovery() {
    state = .notDiscovered
  }
}
