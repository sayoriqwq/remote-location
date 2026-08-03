import Foundation

@MainActor
final class BaselineViewModel: ObservableObject {
  @Published var latitudeText = ""
  @Published var longitudeText = ""
  @Published private(set) var session = GPXBaselineSession()
  @Published private(set) var manualSession = ManualSimulationSession()
  @Published private(set) var selection = LocationSelectionState()
  @Published private(set) var inputError: String?
  @Published private(set) var savedLocations = SavedLocationCollection()
  @Published private(set) var savedLocationError: String?
  @Published private(set) var savedLocationPersistenceError = false

  private var savedLocationRepository: SavedLocationRepository
  private var expirationTask: Task<Void, Never>?
  private var manualExpirationTask: Task<Void, Never>?

  init(savedLocationStore: any SavedLocationStore = FileSavedLocationStore()) {
    if let resetToken = ProcessInfo.processInfo.environment[
      "REMOTE_LOCATION_E2E_SAVED_LOCATIONS_RESET_TOKEN"
    ], let resettableStore = savedLocationStore as? any ResettableSavedLocationStore,
      UserDefaults.standard.string(
        forKey: "remote-location-e2e-saved-locations-reset-token"
      ) != resetToken
    {
      do {
        try resettableStore.reset()
        UserDefaults.standard.set(
          resetToken,
          forKey: "remote-location-e2e-saved-locations-reset-token"
        )
      } catch {
        // The normal load below surfaces the actionable persistence error.
      }
    }

    let repository: SavedLocationRepository
    let initialError: String?
    do {
      repository = try SavedLocationRepository(store: savedLocationStore)
      initialError = nil
    } catch {
      repository = SavedLocationRepository(
        collection: SavedLocationCollection(),
        store: savedLocationStore
      )
      initialError = "Saved Locations could not be loaded."
    }
    savedLocationRepository = repository
    savedLocations = repository.collection
    savedLocationError = initialError
    savedLocationPersistenceError = initialError != nil
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
    }
  }

  func clearSavedLocationError() {
    savedLocationError = nil
    savedLocationPersistenceError = false
  }

  func saveCurrentLocation(named name: String) {
    guard let selected = selection.selected else {
      savedLocationError = "Save a valid Selected Location first."
      savedLocationPersistenceError = false
      return
    }

    do {
      _ = try savedLocationRepository.add(
        name: name,
        coordinate: selected
      )
      savedLocations = savedLocationRepository.collection
      savedLocationError = nil
      savedLocationPersistenceError = false
    } catch let error as SavedLocationError {
      savedLocationError = savedLocationErrorMessage(for: error)
      savedLocationPersistenceError = false
    } catch {
      savedLocationError =
        "Saved Locations could not be saved. Your existing collection is unchanged."
      savedLocationPersistenceError = true
    }
  }

  func renameSavedLocation(id: UUID, to name: String) {
    do {
      try savedLocationRepository.rename(id: id, to: name)
      savedLocations = savedLocationRepository.collection
      savedLocationError = nil
      savedLocationPersistenceError = false
    } catch let error as SavedLocationError {
      savedLocationError = savedLocationErrorMessage(for: error)
      savedLocationPersistenceError = false
    } catch {
      savedLocationError =
        "Saved Locations could not be saved. Your existing collection is unchanged."
      savedLocationPersistenceError = true
    }
  }

  func deleteSavedLocation(id: UUID) {
    do {
      try savedLocationRepository.delete(id: id)
      savedLocations = savedLocationRepository.collection
      savedLocationError = nil
      savedLocationPersistenceError = false
    } catch let error as SavedLocationError {
      savedLocationError = savedLocationErrorMessage(for: error)
      savedLocationPersistenceError = false
    } catch {
      savedLocationError =
        "Saved Locations could not be saved. Your existing collection is unchanged."
      savedLocationPersistenceError = true
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

  private func savedLocationErrorMessage(for error: SavedLocationError) -> String {
    switch error {
    case .emptyName:
      "Saved Location names cannot be blank. Enter a name and try again."
    case .duplicateName:
      "A Saved Location with this name already exists. Choose a different name."
    case .duplicateIdentity:
      "This Saved Location already exists. Try again."
    case .notFound:
      "This Saved Location no longer exists."
    case .unsupportedVersion:
      "Saved Locations use an unsupported version."
    }
  }
}
