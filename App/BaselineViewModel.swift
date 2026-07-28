import Foundation

@MainActor
final class BaselineViewModel: ObservableObject {
  @Published var latitudeText = ""
  @Published var longitudeText = ""
  @Published private(set) var session = GPXBaselineSession()
  @Published private(set) var manualSession = ManualSimulationSession()
  @Published private(set) var selection = LocationSelectionState()
  @Published private(set) var inputError: String?
  private var expirationTask: Task<Void, Never>?
  private var manualExpirationTask: Task<Void, Never>?

  func saveSelection() {
    do {
      let selection = try SelectedLocation.parse(
        latitude: latitudeText,
        longitude: longitudeText
      )
      _ = select(selection, source: .manual)
    } catch {
      inputError = error.localizedDescription
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
    return true
  }

  func beginObservationWindow(at date: Date = Date()) {
    do {
      try session.beginObservationWindow(at: date)
      inputError = nil
      expirationTask?.cancel()
      expirationTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(15_001))
        guard !Task.isCancelled else {
          return
        }
        self?.session.expireObservationWindow(
          at: date.addingTimeInterval(15.001)
        )
      }
    } catch {
      inputError = "Save a valid Selected Location first."
    }
  }

  func record(_ observation: LocationObservation) {
    session.record(observation)
    manualSession.record(observation)
  }

  func beginManualApply(at date: Date = Date()) -> ManualSimulationRequest? {
    do {
      let request = try manualSession.beginApply(requestID: UUID(), at: date)
      inputError = nil
      manualExpirationTask?.cancel()
      manualExpirationTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(15_001))
        guard !Task.isCancelled else { return }
        self?.manualSession.expire(
          at: date.addingTimeInterval(15.001)
        )
      }
      return request
    } catch {
      inputError = "Save a valid Selected Location first."
      return nil
    }
  }

  func receiveApplyResponse(
    _ response: ControllerLinkResponse,
    for request: ManualSimulationRequest,
    at date: Date = Date()
  ) {
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
    case .failed(let responseID, let reason):
      _ = manualSession.fail(
        requestID: responseID,
        reason: map(reason)
      )
    case .rejected(let responseID, let reason):
      _ = manualSession.fail(
        requestID: responseID,
        reason: .requestRejected(stableCode: reason.rawValue)
      )
    case .status, .paired, .stopped:
      _ = manualSession.fail(
        requestID: request.requestID,
        reason: .responseIdentityMismatch
      )
    }
  }

  func beginStop() -> UUID? {
    guard manualSession.activeAppliedRequest != nil else {
      return nil
    }
    let requestID = UUID()
    manualSession.beginStop(requestID: requestID)
    return requestID
  }

  func receiveStopResponse(
    _ response: ControllerLinkResponse,
    for requestID: UUID
  ) {
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
    case .failed(let responseID, let reason):
      _ = manualSession.failStop(
        requestID: responseID,
        reason: map(reason)
      )
    case .rejected(let responseID, let reason):
      _ = manualSession.failStop(
        requestID: responseID,
        reason: .requestRejected(stableCode: reason.rawValue)
      )
    case .status, .paired, .applied:
      _ = manualSession.failStop(
        requestID: requestID,
        reason: .responseIdentityMismatch
      )
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
