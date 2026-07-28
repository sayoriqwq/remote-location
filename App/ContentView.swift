import CoreLocation
import SwiftUI

struct ContentView: View {
  @StateObject private var observer = LocationObserver()
  @StateObject private var model = BaselineViewModel()
  @StateObject private var controllerLink = ControllerLinkViewModel()
  @State private var showingLocationPicker = false
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      Form {
        controllerLinkSection
        selectionSection
        simulationSection
        observationSection
        baselineSection
        limitationsSection
      }
      .navigationTitle("Location Learning")
    }
    .task {
      if locationPermissionFixture == nil {
        observer.start()
      }
      if localNetworkPermissionFixture == nil {
        controllerLink.start()
      }
    }
    .onReceive(observer.$latestObservation.compactMap { $0 }) { observation in
      model.record(observation)
    }
    .sheet(isPresented: $showingLocationPicker) {
      LocationPickerView(selected: model.selection.selected) { location, source in
        model.select(location, source: source)
      }
    }
  }

  private var controllerLinkSection: some View {
    Section("Mac Controller") {
      LabeledContent("Local Network Permission") {
        Text(localNetworkPermissionDescription)
          .accessibilityIdentifier("local-network-permission-status")
      }

      LabeledContent("Controller Link") {
        Text(controllerLinkStatus)
          .accessibilityIdentifier("controller-link-status")
      }

      LabeledContent("Active Test Device / Xcode") {
        Text(xcodeDeviceWorkflowDescription)
          .accessibilityIdentifier("xcode-device-workflow-status")
      }

      LabeledContent("Injection Backend") {
        Text(backendReadinessDescription)
          .accessibilityIdentifier("controller-backend-status")
      }

      LabeledContent("Applied Simulation") {
        Text(appliedSimulationDescription)
          .accessibilityIdentifier("applied-simulation-status")
      }

      LabeledContent("Verified Simulation") {
        Text(verifiedSimulationDescription)
          .accessibilityIdentifier("verified-simulation-status")
      }

      if case .awaitingPairing = controllerLink.state {
        TextField("6-digit pairing code", text: $controllerLink.pairingCode)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .accessibilityIdentifier("controller-pairing-code")
        Button("Pair Controller") {
          controllerLink.pair()
        }
        .disabled(!controllerLink.canPair)
        .accessibilityIdentifier("pair-controller")
      }

      if case .unavailable(.pairingFailed) = controllerLink.state {
        TextField("6-digit pairing code", text: $controllerLink.pairingCode)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .accessibilityIdentifier("controller-pairing-code")
        Button("Try Pairing Code Again") {
          controllerLink.pair()
        }
        .disabled(!controllerLink.canPair)
        .accessibilityIdentifier("pair-controller")
      }

      if effectiveLocalNetworkPermission == .notYetConfirmed {
        Text(
          "Local Network access is not yet confirmed. iOS decides when to show the prompt; discovery readiness confirms access without reading a private permission API."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      if effectiveLocalNetworkPermission == .denied {
        Text(
          "Allow Local Network access in Settings → Privacy & Security → Local Network, then retry."
        )
        .font(.footnote)
        Button("Open Local Network Settings") {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        .accessibilityIdentifier("open-local-network-settings")
      }

      if shouldShowControllerRetry {
        Button("Retry Controller Discovery") {
          controllerLink.retry()
        }
        .accessibilityIdentifier("retry-controller-discovery")
      }

      if case .connected = controllerLink.state, controllerLink.backendReadiness != .ready {
        Button("Refresh Injection Backend Status") {
          controllerLink.refreshReadiness()
        }
        .accessibilityIdentifier("refresh-controller-readiness")
      }
    }
  }

  private var selectionSection: some View {
    Section("Selected Location") {
      TextField("Latitude (-90…90)", text: $model.latitudeText)
        .keyboardType(.numbersAndPunctuation)
        .accessibilityIdentifier("latitude-input")
      TextField("Longitude (-180…180)", text: $model.longitudeText)
        .keyboardType(.numbersAndPunctuation)
        .accessibilityIdentifier("longitude-input")
      Button("Save Selected Location") {
        model.saveSelection()
      }
      .accessibilityIdentifier("save-selection")

      Button("Choose on Map or Search") {
        showingLocationPicker = true
      }
      .accessibilityIdentifier("open-location-picker")

      if let selected = model.selection.selected {
        LabeledContent("Latitude") {
          Text(selected.latitude.formatted(.number.precision(.fractionLength(6))))
            .accessibilityIdentifier("selected-latitude")
        }
        LabeledContent("Longitude") {
          Text(selected.longitude.formatted(.number.precision(.fractionLength(6))))
            .accessibilityIdentifier("selected-longitude")
        }
        if let source = model.selection.source {
          LabeledContent("Selected via") {
            Text(selectionSourceDescription(source))
              .accessibilityIdentifier("selection-source")
          }
        }
      } else {
        Text("No location selected")
          .foregroundStyle(.secondary)
      }

      if let inputError = model.inputError {
        Text(inputError)
          .foregroundStyle(.red)
          .accessibilityIdentifier("selection-error")
      }
    }
  }

  private var simulationSection: some View {
    Section("Static Simulation") {
      Text(
        "Apply sends only the current Selected Location to your paired Mac controller. Applied confirms the backend; Verified additionally requires a fresh nearby observation in this app."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      Button(model.isApplying ? "Applying…" : "Apply Selected Location") {
        guard let request = model.beginManualApply() else { return }
        Task {
          let response = await controllerLink.apply(request)
          model.receiveApplyResponse(response, for: request)
        }
      }
      .disabled(
        model.selection.selected == nil
          || model.isApplying
      )
      .accessibilityIdentifier("apply-selected-location")

      manualSimulationStatus

      if let activeRequest = model.manualSession.activeAppliedRequest {
        Label("Applied Simulation acknowledged", systemImage: "checkmark.circle")
          .foregroundStyle(.blue)
          .accessibilityIdentifier("applied-acknowledgement")
        LabeledContent("Active Applied Request", value: activeRequest.requestID.uuidString)
          .font(.footnote.monospaced())
          .accessibilityIdentifier("active-simulation-request-id")
      }

      Button(model.isStopping ? "Stopping…" : "Stop Simulation") {
        guard let requestID = model.beginStop() else { return }
        Task {
          let response = await controllerLink.stop(requestID: requestID)
          model.receiveStopResponse(response, for: requestID)
        }
      }
      .disabled(
        model.manualSession.activeAppliedRequest == nil
          || model.isStopping
      )
      .accessibilityIdentifier("stop-simulation")

      manualStopStatus
    }
  }

  @ViewBuilder
  private var manualSimulationStatus: some View {
    switch model.manualSession.status {
    case .noSelection:
      Text("Save a Selected Location to begin.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("simulation-status")
    case .selected:
      Text("Selected — waiting to apply")
        .accessibilityIdentifier("simulation-status")
    case .applying(let request):
      Label("Applying to the Injection Backend…", systemImage: "arrow.up.circle")
        .foregroundStyle(.orange)
        .accessibilityIdentifier("simulation-status")
      requestIdentity(request)
    case .applied(let request):
      Label("Applied Simulation — waiting for a fresh observation", systemImage: "checkmark.circle")
        .foregroundStyle(.blue)
        .accessibilityIdentifier("simulation-status")
      requestIdentity(request)
    case .appliedNotVerified(let request, let issue):
      Label("Applied, but not verified", systemImage: "exclamationmark.circle")
        .foregroundStyle(.orange)
        .accessibilityIdentifier("simulation-status")
      Text(verificationIssueDescription(issue))
        .font(.footnote)
        .accessibilityIdentifier("simulation-diagnostic")
      requestIdentity(request)
    case .verified(let request, let evidence):
      Label("Verified Simulation in this Learning App", systemImage: "checkmark.seal.fill")
        .foregroundStyle(.green)
        .accessibilityIdentifier("simulation-status")
      LabeledContent("Elapsed") {
        Text("\(evidence.elapsedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
          .accessibilityIdentifier("simulation-elapsed")
      }
      LabeledContent("Distance") {
        Text("\(evidence.distanceMeters.formatted(.number.precision(.fractionLength(2)))) m")
          .accessibilityIdentifier("simulation-distance")
      }
      requestIdentity(request)
    case .failed(let request, let failure):
      Label("Simulation request failed", systemImage: "xmark.circle")
        .foregroundStyle(.red)
        .accessibilityIdentifier("simulation-status")
      Text(manualFailureDescription(failure))
        .font(.footnote)
        .accessibilityIdentifier("simulation-diagnostic")
      requestIdentity(request)
    case .stopped:
      Text("No Applied Simulation is active.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("simulation-status")
    }
  }

  private func requestIdentity(_ request: ManualSimulationRequest) -> some View {
    LabeledContent("Request") {
      Text(request.requestID.uuidString)
        .font(.footnote.monospaced())
        .accessibilityIdentifier("simulation-request-id")
    }
  }

  @ViewBuilder
  private var manualStopStatus: some View {
    switch model.manualSession.stopStatus {
    case .idle:
      EmptyView()
    case .stopping(let requestID):
      Label("Stopping the active simulation…", systemImage: "stop.circle")
        .foregroundStyle(.orange)
        .accessibilityIdentifier("stop-status")
      LabeledContent("Stop Request", value: requestID.uuidString)
        .font(.footnote.monospaced())
    case .stopped:
      Label("Injection Backend cleared", systemImage: "stop.circle.fill")
        .foregroundStyle(.green)
        .accessibilityIdentifier("stop-status")
      Text(
        "The simulation proxy is inactive. A fresh physical-location callback is separate and may not arrive immediately."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    case .failed(_, let failure):
      Label("Could not stop the active simulation", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
        .accessibilityIdentifier("stop-status")
      Text(manualFailureDescription(failure))
        .font(.footnote)
        .accessibilityIdentifier("stop-diagnostic")
    }
  }

  private var observationSection: some View {
    Section("Latest Observed Location") {
      LabeledContent("Location Permission") {
        Text(authorizationDescription)
          .accessibilityIdentifier("location-permission-status")
      }

      switch effectiveLocationPermission {
      case .notDetermined:
        Text(
          "Choose Allow While Using App when iOS asks so the app can verify a fresh observation."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      case .denied:
        Text("Location access is denied. Enable While Using the App in Settings, then return here.")
          .font(.footnote)
        Button("Open Location Settings") {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        .accessibilityIdentifier("open-location-settings")
      case .restricted:
        Text(
          "Location access is restricted by device policy or parental controls; this app cannot change that setting."
        )
        .font(.footnote)
      case .authorized, .unknown:
        EmptyView()
      }

      if let observation = model.session.latestObservation {
        LabeledContent("Latitude") {
          Text(observation.coordinate.latitude.formatted(.number.precision(.fractionLength(6))))
            .accessibilityIdentifier("observed-latitude")
        }
        LabeledContent("Longitude") {
          Text(observation.coordinate.longitude.formatted(.number.precision(.fractionLength(6))))
            .accessibilityIdentifier("observed-longitude")
        }
        LabeledContent("Timestamp") {
          Text(observation.timestamp.formatted(date: .numeric, time: .standard))
            .accessibilityIdentifier("observed-timestamp")
        }
        LabeledContent(
          "Horizontal accuracy",
          value:
            "\(observation.horizontalAccuracy.formatted(.number.precision(.fractionLength(1)))) m")
        LabeledContent("Last observation simulated") {
          Text(simulationDescription(observation.isSimulatedBySoftware))
            .accessibilityIdentifier("observation-source")
        }
        Text(
          "This is the last successful Core Location observation. It may remain after a simulation stops and does not indicate an active simulation."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("observation-recency-note")
      } else {
        LabeledContent("Latitude") {
          Text("Unavailable")
            .accessibilityIdentifier("observed-latitude")
        }
        LabeledContent("Longitude") {
          Text("Unavailable")
            .accessibilityIdentifier("observed-longitude")
        }
        LabeledContent("Last observation simulated") {
          Text("Unavailable")
            .accessibilityIdentifier("observation-source")
        }
        Text("Waiting for a Core Location observation…")
          .foregroundStyle(.secondary)
      }

      if let errorMessage = observer.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .accessibilityIdentifier("location-error")
      }
    }
  }

  private var baselineSection: some View {
    Section("GPX Observation Baseline") {
      Text(
        "This button does not apply a location. Start the 15-second window, then choose a GPX location from Xcode."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      Button("Start 15-second Observation Window") {
        model.beginObservationWindow()
      }
      .disabled(model.session.selected == nil)
      .accessibilityIdentifier("start-observation-window")

      if let requestedAt = model.session.requestedAt {
        LabeledContent("Requested", value: requestedAt.formatted(date: .numeric, time: .standard))
      }

      matchStatus
    }
  }

  @ViewBuilder
  private var matchStatus: some View {
    switch model.session.match {
    case .matched(let evidence):
      Label("GPX baseline matched", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityIdentifier("match-status")
      LabeledContent("Elapsed") {
        Text("\(evidence.elapsedSeconds.formatted(.number.precision(.fractionLength(2)))) s")
          .accessibilityIdentifier("match-elapsed")
      }
      LabeledContent("Distance") {
        Text("\(evidence.distanceMeters.formatted(.number.precision(.fractionLength(2)))) m")
          .accessibilityIdentifier("match-distance")
      }
    case .notAfterRequest:
      Label(
        "Observation is not newer than this request", systemImage: "clock.badge.exclamationmark"
      )
      .accessibilityIdentifier("match-status")
    case .timedOut(let elapsedSeconds):
      Label(
        "Observation arrived after 15 seconds (\(elapsedSeconds.formatted(.number.precision(.fractionLength(2)))) s)",
        systemImage: "timer"
      )
      .accessibilityIdentifier("match-status")
    case .tooFar(let distanceMeters):
      Label(
        "Observation is \(distanceMeters.formatted(.number.precision(.fractionLength(2)))) m away",
        systemImage: "location.slash"
      )
      .accessibilityIdentifier("match-status")
    case nil:
      Text("No baseline result yet")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("match-status")
    }
  }

  private var limitationsSection: some View {
    Section("Scope") {
      Text(
        "A match only proves that this Learning App observed the selected coordinate. It does not prove cross-app propagation."
      )
      .font(.footnote)
    }
  }

  private var authorizationDescription: String {
    switch effectiveLocationPermission {
    case .notDetermined: "Not requested"
    case .restricted: "Restricted"
    case .denied: "Denied"
    case .authorized: "While Using the App"
    case .unknown: "Unknown"
    }
  }

  private func selectionSourceDescription(_ source: LocationSelectionSource) -> String {
    switch source {
    case .manual: "Manual coordinates"
    case .map: "Map"
    case .search: "Place search"
    }
  }

  private var controllerLinkStatus: String {
    switch controllerLink.state {
    case .notDiscovered:
      "Searching for your Mac controller…"
    case .awaitingPairing:
      "Controller found — enter the code shown on your Mac"
    case .connected:
      "Trusted controller connected"
    case .unavailable(.disconnected):
      "Controller disconnected"
    case .unavailable(.tlsIdentityMismatch):
      "Controller identity changed — connection rejected"
    case .unavailable(.pairingFailed):
      "Pairing code was rejected"
    case .unavailable(.transportUnavailable):
      "Controller unavailable"
    case .localNetworkDenied:
      "Local Network access is denied"
    }
  }

  private var localNetworkPermissionDescription: String {
    switch effectiveLocalNetworkPermission {
    case .notYetConfirmed:
      "Not yet confirmed"
    case .allowed:
      "Allowed"
    case .denied:
      "Denied"
    }
  }

  private var effectiveLocationPermission: LocationPermissionState {
    locationPermissionFixture ?? observer.permissionState
  }

  private var effectiveLocalNetworkPermission: LocalNetworkPermissionState {
    localNetworkPermissionFixture ?? controllerLink.localNetworkPermission
  }

  private var locationPermissionFixture: LocationPermissionState? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["REMOTE_LOCATION_E2E_LOCATION_PERMISSION"] {
      case "not-determined":
        return .notDetermined
      case "allowed":
        return .authorized
      case "denied":
        return .denied
      case "restricted":
        return .restricted
      default:
        return nil
      }
    #else
      nil
    #endif
  }

  private var localNetworkPermissionFixture: LocalNetworkPermissionState? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment[
        "REMOTE_LOCATION_E2E_LOCAL_NETWORK_PERMISSION"
      ] {
      case "not-yet-confirmed":
        return .notYetConfirmed
      case "allowed":
        return .allowed
      case "denied":
        return .denied
      default:
        return nil
      }
    #else
      nil
    #endif
  }

  private var xcodeDeviceWorkflowDescription: String {
    switch controllerLink.backendReadiness {
    case .ready:
      "Ready"
    case .unavailable(.noActiveDevice):
      "No Active Test Device — run doctor on the Mac"
    case .unavailable(.sessionNotReady):
      "Not ready — run doctor on the Mac"
    case .unavailable(.backendUnavailable), .unavailable(.timedOut):
      "Unavailable — run doctor on the Mac"
    case .unavailable:
      "Controller reported a workflow failure"
    case nil:
      "Waiting for Controller Link"
    }
  }

  private var backendReadinessDescription: String {
    switch controllerLink.backendReadiness {
    case .ready:
      "devicectl ready"
    case .unavailable(let reason):
      controllerFailureDescription(reason)
    case nil:
      if case .connected = controllerLink.state {
        "Checking…"
      } else {
        "Unavailable until connected"
      }
    }
  }

  private var appliedSimulationDescription: String {
    model.manualSession.activeAppliedRequest == nil ? "Inactive" : "Acknowledged"
  }

  private var verifiedSimulationDescription: String {
    if case .verified = model.manualSession.status {
      return "Verified by a fresh app observation"
    }
    return "Not verified"
  }

  private func manualFailureDescription(_ failure: ManualSimulationFailure) -> String {
    switch failure {
    case .responseIdentityMismatch:
      "The response did not match this request. Nothing was marked Applied; retry after checking the controller."
    case .controllerUnavailable:
      "The trusted controller became unavailable. Retry discovery without changing the Selected Location."
    case .requestRejected(let stableCode):
      "The controller rejected the request (\(stableCode)). Check the backend status and retry."
    }
  }

  private func verificationIssueDescription(_ issue: AppliedVerificationIssue) -> String {
    switch issue {
    case .notAfterRequest:
      "The observation is older than the current request. Wait for a fresh location update."
    case .timedOut(let elapsedSeconds):
      "No matching observation arrived within 15 seconds (\(elapsedSeconds.formatted(.number.precision(.fractionLength(2)))) s)."
    case .tooFar(let distanceMeters):
      "The latest observation is \(distanceMeters.formatted(.number.precision(.fractionLength(2)))) m away; it must be within 25 m."
    }
  }

  private func controllerFailureDescription(_ reason: ControllerCommandFailure) -> String {
    switch reason {
    case .invalidCoordinate:
      "Invalid coordinate"
    case .noActiveDevice:
      "No Active Test Device"
    case .sessionNotReady:
      "Xcode device workflow is not ready"
    case .backendUnavailable:
      "Injection Backend is unavailable"
    case .timedOut:
      "Injection Backend timed out"
    case .authenticationFailed:
      "Controller Link authorization failed"
    case .clearFailed:
      "The active simulation could not be cleared"
    case .controllerUnavailable:
      "Controller unavailable"
    case .responseIdentityMismatch:
      "Controller response mismatch"
    }
  }

  private var shouldShowControllerRetry: Bool {
    switch controllerLink.state {
    case .unavailable(.disconnected), .unavailable(.transportUnavailable), .localNetworkDenied:
      true
    default:
      false
    }
  }

  private func simulationDescription(_ value: Bool?) -> String {
    switch value {
    case true: "Yes"
    case false: "No"
    case nil: "Unavailable"
    }
  }
}
