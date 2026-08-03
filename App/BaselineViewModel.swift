import Foundation

@MainActor
final class BaselineViewModel: ObservableObject {
  @Published var latitudeText = ""
  @Published var longitudeText = ""
  @Published private(set) var session = GPXBaselineSession()
  @Published private(set) var manualSession = ManualSimulationSession()
  @Published private(set) var selection = LocationSelectionState()
  @Published private(set) var inputError: String?
  private let diagnostics: SimulationDiagnosticRecorder?
  private var expirationTask: Task<Void, Never>?
  private var manualExpirationTask: Task<Void, Never>?

  init(diagnostics: SimulationDiagnosticRecorder? = nil) {
    self.diagnostics = diagnostics
  }

  func saveSelection() {
    do {
      let selection = try SelectedLocation.parse(
        latitude: latitudeText,
        longitude: longitudeText
      )
      _ = select(selection, source: .manual)
    } catch {
      inputError = error.localizedDescription
      record(
        kind: "app.selection.rejected",
        fields: ["reason": .text(error.localizedDescription)]
      )
    }
  }

  @discardableResult
  func select(
    _ location: SelectedLocation,
    source: LocationSelectionSource
  ) -> Bool {
    guard !isStopping else {
      inputError = "Finish the current stop request before changing the Selected Location."
      return false
    }

    selection.select(location, source: source)
    session.select(location)
    manualSession.select(location)
    latitudeText = String(
      format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), location.latitude)
    longitudeText = String(
      format: "%.6f",
      locale: Locale(identifier: "en_US_POSIX"),
      location.longitude
    )
    expirationTask?.cancel()
    manualExpirationTask?.cancel()
    inputError = nil
    record(
      kind: "app.selection.replaced",
      fields: [
        "source": .text(source.rawValue),
        "latitude": .number(location.latitude),
        "longitude": .number(location.longitude),
      ]
    )
    return true
  }

  func beginObservationWindow(at date: Date = Date()) {
    do {
      try session.beginObservationWindow(at: date)
      inputError = nil
      record(
        kind: "app.observation-window.started",
        fields: ["requestedAt": .date(date)]
      )
      expirationTask?.cancel()
      expirationTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(15_001))
        guard !Task.isCancelled else {
          return
        }
        self?.session.expireObservationWindow(
          at: date.addingTimeInterval(15.001)
        )
        if case .timedOut = self?.session.match {
          self?.record(
            kind: "app.observation-window.timed-out",
            fields: ["requestedAt": .date(date)]
          )
        }
      }
    } catch {
      inputError = "Save a valid Selected Location first."
      record(kind: "app.observation-window.rejected")
    }
  }

  func record(_ observation: LocationObservation) {
    session.record(observation)
    manualSession.record(observation)
    var fields: SimulationDiagnosticFields = [
      "latitude": .number(observation.coordinate.latitude),
      "longitude": .number(observation.coordinate.longitude),
      "observationTimestamp": .date(observation.timestamp),
      "horizontalAccuracy": .number(observation.horizontalAccuracy),
    ]
    if let simulated = observation.isSimulatedBySoftware {
      fields["isSimulatedBySoftware"] = .boolean(simulated)
    } else {
      fields["isSimulatedBySoftware"] = .null
    }
    let verification = verificationFields()
    fields.merge(verification.fields) { _, new in new }
    record(kind: "app.observation.verification-updated", fields: fields)
    if let requestID = verification.requestID {
      record(
        kind: "app.apply.verification-result",
        requestID: requestID,
        fields: verification.fields
      )
    }
  }

  func beginManualApply(at date: Date = Date()) -> ManualSimulationRequest? {
    do {
      let request = try manualSession.beginApply(requestID: UUID(), at: date)
      inputError = nil
      record(
        kind: "app.apply.started",
        requestID: request.requestID,
        fields: [
          "latitude": .number(request.location.latitude),
          "longitude": .number(request.location.longitude),
          "requestedAt": .date(request.requestedAt),
        ]
      )
      manualExpirationTask?.cancel()
      manualExpirationTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(15_001))
        guard !Task.isCancelled else { return }
        self?.manualSession.expire(at: date.addingTimeInterval(15.001))
        if case .appliedNotVerified(let request, .timedOut) = self?.manualSession.status {
          self?.record(
            kind: "app.apply.verification-timed-out",
            requestID: request.requestID,
            fields: ["requestedAt": .date(request.requestedAt)]
          )
        }
      }
      return request
    } catch {
      inputError = "Save a valid Selected Location first."
      record(kind: "app.apply.rejected")
      return nil
    }
  }

  func receiveApplyResponse(
    _ response: ControllerLinkResponse,
    for request: ManualSimulationRequest,
    at date: Date = Date()
  ) {
    record(
      kind: "app.apply.response",
      requestID: response.requestID,
      fields: responseFields(response)
    )
    guard response.requestID == request.requestID else {
      _ = manualSession.fail(
        requestID: request.requestID,
        reason: .responseIdentityMismatch
      )
      return
    }

    switch response {
    case .applied(let responseID):
      _ = manualSession.acknowledgeApplied(requestID: responseID)
      manualSession.expire(at: date)
      record(kind: "app.apply.acknowledged", requestID: responseID)
    case .failed(let responseID, let reason):
      _ = manualSession.fail(
        requestID: responseID,
        reason: map(reason)
      )
      record(
        kind: "app.apply.failed",
        requestID: responseID,
        fields: ["reason": .text(reason.rawValue)]
      )
    case .rejected(let responseID, let reason):
      _ = manualSession.fail(
        requestID: responseID,
        reason: .requestRejected(stableCode: reason.rawValue)
      )
      record(
        kind: "app.apply.failed",
        requestID: responseID,
        fields: ["reason": .text(reason.rawValue)]
      )
    case .status, .paired, .stopped:
      _ = manualSession.fail(
        requestID: request.requestID,
        reason: .responseIdentityMismatch
      )
      record(
        kind: "app.apply.failed",
        requestID: request.requestID,
        fields: ["reason": .text("responseIdentityMismatch")]
      )
    }
  }

  func beginStop() -> UUID? {
    guard manualSession.activeAppliedRequest != nil else {
      record(kind: "app.stop.rejected", fields: ["reason": .text("no-active-simulation")])
      return nil
    }
    let requestID = UUID()
    manualSession.beginStop(requestID: requestID)
    record(kind: "app.stop.started", requestID: requestID)
    return requestID
  }

  func receiveStopResponse(
    _ response: ControllerLinkResponse,
    for requestID: UUID
  ) {
    record(
      kind: "app.stop.response",
      requestID: response.requestID,
      fields: responseFields(response)
    )
    guard response.requestID == requestID else {
      _ = manualSession.failStop(
        requestID: requestID,
        reason: .responseIdentityMismatch
      )
      return
    }

    switch response {
    case .stopped(let responseID):
      _ = manualSession.acknowledgeStopped(requestID: responseID)
      record(kind: "app.stop.clear-acknowledged", requestID: responseID)
    case .failed(let responseID, let reason):
      _ = manualSession.failStop(
        requestID: responseID,
        reason: map(reason)
      )
      record(
        kind: "app.stop.failed",
        requestID: responseID,
        fields: ["reason": .text(reason.rawValue)]
      )
    case .rejected(let responseID, let reason):
      _ = manualSession.failStop(
        requestID: responseID,
        reason: .requestRejected(stableCode: reason.rawValue)
      )
      record(
        kind: "app.stop.failed",
        requestID: responseID,
        fields: ["reason": .text(reason.rawValue)]
      )
    case .status, .paired, .applied:
      _ = manualSession.failStop(
        requestID: requestID,
        reason: .responseIdentityMismatch
      )
      record(
        kind: "app.stop.failed",
        requestID: requestID,
        fields: ["reason": .text("responseIdentityMismatch")]
      )
    }
  }

  private func record(
    kind: String,
    requestID: UUID? = nil,
    fields: SimulationDiagnosticFields = [:]
  ) {
    guard let diagnostics else { return }
    Task {
      await diagnostics.record(kind: kind, requestID: requestID, fields: fields)
    }
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

  private func verificationFields() -> (
    requestID: UUID?,
    fields: SimulationDiagnosticFields
  ) {
    switch manualSession.status {
    case .verified(let request, let evidence):
      return (
        request.requestID,
        [
          "verificationResult": .text("verified"),
          "elapsedSeconds": .number(evidence.elapsedSeconds),
          "distanceMeters": .number(evidence.distanceMeters),
        ]
      )
    case .appliedNotVerified(let request, let issue):
      var fields: SimulationDiagnosticFields = [
        "verificationResult": .text("not-verified"),
      ]
      switch issue {
      case .notAfterRequest:
        fields["verificationReason"] = .text("observation-not-after-request")
      case .timedOut(let elapsedSeconds):
        fields["verificationReason"] = .text("timed-out")
        fields["elapsedSeconds"] = .number(elapsedSeconds)
      case .tooFar(let distanceMeters):
        fields["verificationReason"] = .text("too-far")
        fields["distanceMeters"] = .number(distanceMeters)
      }
      return (request.requestID, fields)
    case .applied(let request):
      return (
        request.requestID,
        ["verificationResult": .text("awaiting-observation")]
      )
    case .noSelection, .selected, .applying, .failed, .stopped:
      return (nil, ["verificationResult": .text("not-applicable")])
    }
  }

  var isApplying: Bool {
    if case .applying = manualSession.status {
      return true
    }
    return false
  }

  var isStopping: Bool {
    if case .stopping = manualSession.stopStatus {
      return true
    }
    return false
  }

  private func map(_ reason: ControllerCommandFailure) -> ManualSimulationFailure {
    switch reason {
    case .controllerUnavailable:
      .controllerUnavailable
    case .responseIdentityMismatch:
      .responseIdentityMismatch
    default:
      .requestRejected(stableCode: reason.rawValue)
    }
  }
}
