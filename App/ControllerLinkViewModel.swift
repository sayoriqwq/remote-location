import Foundation
import SwiftUI

enum LocalNetworkPermissionState: Equatable {
  case notYetConfirmed
  case allowed
  case denied
}

@MainActor
final class ControllerLinkViewModel: ObservableObject {
  @Published private(set) var state: ControllerLinkState = .notDiscovered
  @Published private(set) var backendReadiness: ControllerBackendReadiness?
  @Published private(set) var localNetworkPermission: LocalNetworkPermissionState =
    .notYetConfirmed
  @Published var pairingCode = ""

  private let discovery: any ControllerDiscovering
  private let link: TrustedControllerLink
  private var discoveryTask: Task<Void, Never>?
  private var mayAttemptConnection = true
  private var hasPairingCandidate = false

  #if DEBUG
    private static let e2eFixtureIdentity = try! ControllerIdentity(
      fingerprint: Data(repeating: 0, count: 32)
    )

    private var usesE2EFixture: Bool {
      ProcessInfo.processInfo.environment[
        "REMOTE_LOCATION_E2E_CONTROLLER_LINK_FIXTURE"
      ] == "1"
    }
  #endif

  init(
    discovery: any ControllerDiscovering = BonjourControllerDiscovery(),
    link: TrustedControllerLink = TrustedControllerLink(
      trust: ControllerTrust(store: KeychainControllerTrustStore()),
      authorizationStore: KeychainControllerAuthorizationStore(),
      transport: NetworkControllerLinkTransport()
    )
  ) {
    self.discovery = discovery
    self.link = link
  }

  func start() {
    guard discoveryTask == nil else { return }
    #if DEBUG
      if usesE2EFixture {
        localNetworkPermission = .allowed
        state = .connected(Self.e2eFixtureIdentity)
        backendReadiness = .ready
        return
      }
    #endif
    discoveryTask = Task { [weak self] in
      guard let self else { return }
      #if DEBUG
        if ProcessInfo.processInfo.environment[
          "REMOTE_LOCATION_E2E_RESET_CONTROLLER_TRUST"
        ] == "1" {
          state = await link.forgetController()
          backendReadiness = nil
        }
      #endif
      for await event in discovery.events() {
        guard !Task.isCancelled else { return }
        await handle(event)
      }
    }
  }

  func retry() {
    discovery.stop()
    discoveryTask?.cancel()
    discoveryTask = nil
    mayAttemptConnection = true
    hasPairingCandidate = false
    pairingCode = ""
    backendReadiness = nil
    localNetworkPermission = .notYetConfirmed
    state = .notDiscovered
    start()
  }

  func pair() {
    guard hasPairingCandidate else { return }
    let code = pairingCode
    Task { [weak self] in
      guard let self else { return }
      state = await link.pair(code: code)
      if case .connected = state {
        pairingCode = ""
        hasPairingCandidate = false
        state = await link.refresh()
        backendReadiness = await link.currentBackendReadiness()
      }
    }
  }

  var canPair: Bool {
    hasPairingCandidate && pairingCode.count == 6 && pairingCode.allSatisfy(\.isNumber)
  }

  var canApply: Bool {
    guard case .connected = state, backendReadiness == .ready else {
      return false
    }
    return true
  }

  var canSendStop: Bool {
    if case .connected = state {
      return true
    }
    return false
  }

  func apply(_ request: ManualSimulationRequest) async -> ControllerLinkResponse {
    #if DEBUG
      if usesE2EFixture {
        return .applied(requestID: request.requestID)
      }
    #endif
    let response = await link.apply(
      requestID: request.requestID,
      latitude: request.location.latitude,
      longitude: request.location.longitude
    )
    state = await link.currentState()
    backendReadiness = await link.currentBackendReadiness()
    return response
  }

  func stop(requestID: UUID) async -> ControllerLinkResponse {
    #if DEBUG
      if usesE2EFixture {
        return .stopped(requestID: requestID)
      }
    #endif
    let response = await link.stop(requestID: requestID)
    state = await link.currentState()
    backendReadiness = await link.currentBackendReadiness()
    return response
  }

  func refreshReadiness() {
    Task { [weak self] in
      guard let self else { return }
      state = await link.refresh()
      backendReadiness = await link.currentBackendReadiness()
    }
  }

  private func handle(_ event: ControllerDiscoveryEvent) async {
    switch event {
    case .localNetworkReady:
      localNetworkPermission = .allowed
    case .notFound:
      if case .connected = state {
        state = await link.disconnected()
        backendReadiness = nil
        mayAttemptConnection = false
      } else if mayAttemptConnection {
        state = .notDiscovered
      }
    case .found(let service):
      localNetworkPermission = .allowed
      guard mayAttemptConnection else { return }
      mayAttemptConnection = false
      state = await link.connect(to: service)
      backendReadiness = await link.currentBackendReadiness()
      if case .awaitingPairing = state {
        hasPairingCandidate = true
      }
    case .localNetworkDenied:
      localNetworkPermission = .denied
      mayAttemptConnection = false
      state = await link.localNetworkPermissionDenied()
      backendReadiness = nil
    case .failed:
      mayAttemptConnection = false
      state = .unavailable(.transportUnavailable)
      backendReadiness = nil
    }
  }
}
