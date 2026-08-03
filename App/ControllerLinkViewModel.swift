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
  private let diagnostics: SimulationDiagnosticPipeline?
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

    private var usesE2EStopFailureFixture: Bool {
      ProcessInfo.processInfo.environment[
        "REMOTE_LOCATION_E2E_CONTROLLER_LINK_FAILURE_FIXTURE"
      ] == "failed-stop"
    }
  #endif

  init(
    discovery: any ControllerDiscovering = BonjourControllerDiscovery(),
    link: TrustedControllerLink = TrustedControllerLink(
      trust: ControllerTrust(store: KeychainControllerTrustStore()),
      authorizationStore: KeychainControllerAuthorizationStore(),
      transport: NetworkControllerLinkTransport()
    ),
    diagnostics: SimulationDiagnosticPipeline? = nil
  ) {
    self.discovery = discovery
    self.link = link
    self.diagnostics = diagnostics
  }

  func start() {
    guard discoveryTask == nil else { return }
    record(kind: "app.controller-link.lifecycle-started")
    #if DEBUG
      if usesE2EFixture {
        localNetworkPermission = .allowed
        state = .connected(Self.e2eFixtureIdentity)
        backendReadiness = .ready
        record(kind: "app.controller-link.connected", fields: ["source": .text("fixture")])
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
    record(kind: "app.controller-link.discovery-retry")
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
    record(kind: "app.controller-link.pairing-submitted")
    Task { [weak self] in
      guard let self else { return }
      state = await link.pair(code: code)
      record(kind: "app.controller-link.pairing-result", fields: stateFields(state))
      if case .connected = state {
        pairingCode = ""
        hasPairingCandidate = false
        state = await link.refresh()
        backendReadiness = await link.currentBackendReadiness()
        record(kind: "app.controller-link.connected", fields: stateFields(state))
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
    record(
      kind: "app.controller-link.apply-started",
      requestID: request.requestID,
      fields: [
        "latitude": .number(request.location.latitude),
        "longitude": .number(request.location.longitude),
      ]
    )
    #if DEBUG
      if usesE2EFixture {
        record(
          kind: "app.controller-link.apply-response",
          requestID: request.requestID,
          fields: ["outcome": .text("applied"), "source": .text("fixture")]
        )
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
    record(
      kind: "app.controller-link.apply-response",
      requestID: response.requestID,
      fields: responseFields(response)
    )
    return response
  }

  func stop(requestID: UUID) async -> ControllerLinkResponse {
    record(kind: "app.controller-link.stop-started", requestID: requestID)
    #if DEBUG
      if usesE2EFixture {
        if usesE2EStopFailureFixture {
          state = .unavailable(.transportUnavailable)
          backendReadiness = nil
          record(
            kind: "app.controller-link.unavailable",
            fields: [
              "state": .text("unavailable"),
              "reason": .text("transport-unavailable"),
              "source": .text("fixture"),
            ]
          )
          record(
            kind: "app.controller-link.connection-failed",
            fields: ["source": .text("fixture")]
          )
          let response = ControllerLinkResponse.failed(
            requestID: requestID,
            reason: .clearFailed
          )
          record(
            kind: "app.controller-link.stop-response",
            requestID: requestID,
            fields: responseFields(response)
          )
          return response
        }
        record(
          kind: "app.controller-link.stop-response",
          requestID: requestID,
          fields: ["outcome": .text("stopped"), "source": .text("fixture")]
        )
        return .stopped(requestID: requestID)
      }
    #endif
    let response = await link.stop(requestID: requestID)
    state = await link.currentState()
    backendReadiness = await link.currentBackendReadiness()
    record(
      kind: "app.controller-link.stop-response",
      requestID: response.requestID,
      fields: responseFields(response)
    )
    return response
  }

  func refreshReadiness() {
    Task { [weak self] in
      guard let self else { return }
      state = await link.refresh()
      backendReadiness = await link.currentBackendReadiness()
      record(kind: "app.controller-link.readiness-refreshed", fields: stateFields(state))
    }
  }

  private func handle(_ event: ControllerDiscoveryEvent) async {
    record(kind: "app.controller-link.discovery-event", fields: eventFields(event))
    switch event {
    case .localNetworkReady:
      localNetworkPermission = .allowed
    case .notFound:
      if case .connected = state {
        state = await link.disconnected()
        backendReadiness = nil
        mayAttemptConnection = false
        record(kind: "app.controller-link.disconnected")
      } else if mayAttemptConnection {
        state = .notDiscovered
      }
    case .found(let service):
      localNetworkPermission = .allowed
      guard mayAttemptConnection else { return }
      mayAttemptConnection = false
      state = await link.connect(to: service)
      backendReadiness = await link.currentBackendReadiness()
      record(kind: "app.controller-link.connection-result", fields: stateFields(state))
      if case .awaitingPairing = state {
        hasPairingCandidate = true
      }
    case .localNetworkDenied:
      localNetworkPermission = .denied
      mayAttemptConnection = false
      state = await link.localNetworkPermissionDenied()
      backendReadiness = nil
      record(kind: "app.controller-link.local-network-denied")
    case .failed:
      mayAttemptConnection = false
      state = .unavailable(.transportUnavailable)
      backendReadiness = nil
      record(kind: "app.controller-link.connection-failed")
    }
  }

  private func record(
    kind: String,
    requestID: UUID? = nil,
    fields: SimulationDiagnosticFields = [:]
  ) {
    guard let diagnostics else { return }
    diagnostics.record(kind: kind, requestID: requestID, fields: fields)
  }

  private func eventFields(_ event: ControllerDiscoveryEvent) -> SimulationDiagnosticFields {
    switch event {
    case .localNetworkReady:
      return ["event": .text("local-network-ready")]
    case .notFound:
      return ["event": .text("not-found")]
    case .found:
      return ["event": .text("found")]
    case .localNetworkDenied:
      return ["event": .text("local-network-denied")]
    case .failed(let failure):
      return ["event": .text("failed"), "reason": .text(String(describing: failure))]
    }
  }

  private func stateFields(_ state: ControllerLinkState) -> SimulationDiagnosticFields {
    var fields: SimulationDiagnosticFields
    switch state {
    case .notDiscovered:
      fields = ["state": .text("not-discovered")]
    case .awaitingPairing:
      fields = ["state": .text("pairing-required")]
    case .connected:
      fields = ["state": .text("connected")]
    case .unavailable(let failure):
      fields = ["state": .text("unavailable"), "reason": .text(String(describing: failure))]
    case .localNetworkDenied:
      fields = ["state": .text("local-network-denied")]
    }
    if let backendReadiness {
      switch backendReadiness {
      case .ready:
        fields["backendReadiness"] = .text("ready")
      case .unavailable(let reason):
        fields["backendReadiness"] = .text("unavailable")
        fields["backendReadinessReason"] = .text(reason.rawValue)
      }
    } else {
      fields["backendReadiness"] = .null
    }
    return fields
  }

  private func responseFields(_ response: ControllerLinkResponse) -> SimulationDiagnosticFields {
    switch response {
    case .status(_, let readiness):
      return ["outcome": .text(String(describing: readiness))]
    case .paired:
      return ["outcome": .text("paired")]
    case .applied:
      return ["outcome": .text("applied")]
    case .stopped:
      return ["outcome": .text("stopped")]
    case .failed(_, let reason):
      return ["outcome": .text("failed"), "reason": .text(reason.rawValue)]
    case .rejected(_, let reason):
      return ["outcome": .text("rejected"), "reason": .text(reason.rawValue)]
    }
  }
}
