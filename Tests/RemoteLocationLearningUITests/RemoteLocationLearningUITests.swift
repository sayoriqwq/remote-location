import CoreLocation
import XCTest

@MainActor
final class RemoteLocationLearningUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    MainActor.assumeIsolated {
      XCUIDevice.shared.location = nil
    }
    addUIInterruptionMonitor(withDescription: "Location permission") { alert in
      MainActor.assumeIsolated {
        for title in ["Allow While Using App", "使用 App 时允许", "使用 App 期间允许"] {
          let allow = alert.buttons[title]
          if allow.exists {
            allow.tap()
            return true
          }
        }

        let localizedAllow = alert.buttons.matching(
          NSPredicate(
            format:
              "(label CONTAINS[c] %@ AND NOT label BEGINSWITH[c] %@) OR (label CONTAINS %@ AND NOT label CONTAINS %@)",
            "Allow",
            "Don",
            "允许",
            "不允许"
          )
        ).firstMatch
        if localizedAllow.exists {
          localizedAllow.tap()
          return true
        }
        return false
      }
    }
  }

  override func tearDown() {
    MainActor.assumeIsolated {
      XCUIDevice.shared.location = nil
    }
    super.tearDown()
  }

  func testLearningAppExposesPublicGateObservationSeam() {
    let app = XCUIApplication()
    app.launch()
    app.tap()

    let latitude = app.textFields["latitude-input"]
    scrollUp(until: latitude, in: app)
    XCTAssertTrue(latitude.waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["longitude-input"].exists)
    XCTAssertTrue(app.buttons["save-selection"].exists)

    let observedLatitude = app.staticTexts["observed-latitude"]
    scrollUp(until: observedLatitude, in: app)
    XCTAssertTrue(observedLatitude.waitForExistence(timeout: 5))

    let observedLongitude = app.staticTexts["observed-longitude"]
    scrollUp(until: observedLongitude, in: app)
    XCTAssertTrue(observedLongitude.waitForExistence(timeout: 5))

    let observationSource = app.staticTexts["observation-source"]
    scrollUp(until: observationSource, in: app)
    XCTAssertTrue(observationSource.waitForExistence(timeout: 5))

    let startObservation = app.buttons["start-observation-window"]
    scrollUp(until: startObservation, in: app)
    XCTAssertTrue(startObservation.waitForExistence(timeout: 5))

    let matchStatus = app.staticTexts["match-status"]
    scrollUp(until: matchStatus, in: app)
    XCTAssertTrue(matchStatus.waitForExistence(timeout: 5))
  }

  func testPermissionFixturesKeepDeniedAndRestrictedRecoveryDistinct() {
    let denied = permissionFixtureApp(location: "denied", localNetwork: "denied")
    denied.launch()

    let localNetworkStatus = denied.staticTexts["local-network-permission-status"]
    XCTAssertTrue(localNetworkStatus.waitForExistence(timeout: 5))
    XCTAssertTrue(localNetworkStatus.label.hasSuffix("Denied"))
    let localNetworkSettings = denied.buttons["open-local-network-settings"]
    scrollUp(until: localNetworkSettings, in: denied)
    XCTAssertTrue(localNetworkSettings.waitForExistence(timeout: 5))

    let deniedLocation = denied.staticTexts["location-permission-status"]
    scrollUp(until: deniedLocation, in: denied)
    XCTAssertTrue(deniedLocation.waitForExistence(timeout: 5))
    XCTAssertTrue(deniedLocation.label.hasSuffix("Denied"))
    let locationSettings = denied.buttons["open-location-settings"]
    scrollUpInSmallSteps(until: locationSettings, in: denied)
    XCTAssertTrue(locationSettings.waitForExistence(timeout: 5))
    denied.terminate()

    let restricted = permissionFixtureApp(location: "restricted", localNetwork: "allowed")
    restricted.launch()

    let allowedLocalNetwork = restricted.staticTexts["local-network-permission-status"]
    XCTAssertTrue(allowedLocalNetwork.waitForExistence(timeout: 5))
    XCTAssertTrue(allowedLocalNetwork.label.hasSuffix("Allowed"))
    let restrictedLocation = restricted.staticTexts["location-permission-status"]
    scrollUp(until: restrictedLocation, in: restricted)
    XCTAssertTrue(restrictedLocation.waitForExistence(timeout: 5))
    XCTAssertTrue(restrictedLocation.label.hasSuffix("Restricted"))
    XCTAssertFalse(restricted.buttons["open-location-settings"].exists)
  }

  func testPublicLocationSetAndReplaceAreVerifiedByLearningApp() {
    let app = XCUIApplication()
    if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
      app.resetAuthorizationStatus(for: .location)
    }
    app.launch()
    app.tap()
    defer { XCUIDevice.shared.location = nil }

    let primer = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
    XCUIDevice.shared.location = XCUILocation(
      location: CLLocation(latitude: primer.latitude, longitude: primer.longitude)
    )
    waitForObservedCoordinate(primer, in: app)

    let coordinateA = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    let coordinateB = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)

    applyAndVerify(coordinateA, in: app)
    applyAndVerify(coordinateB, in: app)
  }

  func testMapSelectionReachesTheFreshObservationVerificationSeam() {
    let app = XCUIApplication()
    app.launchEnvironment["REMOTE_LOCATION_E2E_CONTROLLER_LINK_FIXTURE"] = "1"
    app.launch()
    app.tap()

    openLocationPicker(in: app)

    XCTAssertTrue(app.otherElements["location-map"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["use-map-center"].exists)
    app.buttons["use-map-center"].tap()
    XCTAssertTrue(
      app.staticTexts["location-selection-confirmation"].waitForExistence(timeout: 5)
    )
    app.buttons["close-location-picker"].tap()

    let selectionSource = app.staticTexts["selection-source"]
    scrollUp(until: selectionSource, in: app)
    XCTAssertTrue(selectionSource.waitForExistence(timeout: 5))
    XCTAssertTrue(selectionSource.label.hasSuffix("Map"))
    let selectedStatus = app.staticTexts.matching(identifier: "simulation-status")
      .matching(NSPredicate(format: "label == %@", "Selected — waiting to apply"))
      .firstMatch
    for _ in 0..<4 where !selectedStatus.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(selectedStatus.waitForExistence(timeout: 5))

    let coordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    scrollToTop(in: app)
    let selectedLatitude = app.staticTexts["selected-latitude"]
    let selectedLongitude = app.staticTexts["selected-longitude"]
    scrollUp(until: selectedLatitude, in: app)
    XCTAssertTrue(selectedLatitude.waitForExistence(timeout: 5))
    scrollUp(until: selectedLongitude, in: app)
    XCTAssertTrue(selectedLongitude.waitForExistence(timeout: 5))
    XCTAssertTrue(selectedLatitude.label.hasSuffix("31.230400"))
    XCTAssertTrue(selectedLongitude.label.hasSuffix("121.473700"))
    applyAndVerifySimulation(of: coordinate, in: app)
  }

  func testSearchResultReachesTheFreshObservationVerificationSeam() {
    let app = XCUIApplication()
    app.launchEnvironment["REMOTE_LOCATION_E2E_SEARCH_FIXTURE"] = "1"
    app.launchEnvironment["REMOTE_LOCATION_E2E_CONTROLLER_LINK_FIXTURE"] = "1"
    app.launch()
    app.tap()

    openLocationPicker(in: app)
    let field = app.textFields["place-search-input"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("fixture")
    app.buttons["search-places"].tap()

    let result = app.buttons["place-search-result"]
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    result.tap()
    waitForSelectionConfirmation(in: app)
    app.buttons["close-location-picker"].tap()

    scrollToTop(in: app)
    let selectionSource = app.staticTexts["selection-source"]
    let selectedLatitude = app.staticTexts["selected-latitude"]
    let selectedLongitude = app.staticTexts["selected-longitude"]
    scrollUp(until: selectionSource, in: app)
    XCTAssertTrue(selectionSource.waitForExistence(timeout: 5))
    scrollUp(until: selectedLatitude, in: app)
    XCTAssertTrue(selectedLatitude.waitForExistence(timeout: 5))
    scrollUp(until: selectedLongitude, in: app)
    XCTAssertTrue(selectedLongitude.waitForExistence(timeout: 5))
    XCTAssertTrue(selectionSource.label.hasSuffix("Place search"))
    XCTAssertTrue(selectedLatitude.label.hasSuffix("35.676200"))
    XCTAssertTrue(selectedLongitude.label.hasSuffix("139.650300"))
    applyAndVerifySimulation(
      of: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
      in: app
    )
  }

  func testSearchEmptyAndFailureStatesPreserveThePreviousSelection() {
    let app = XCUIApplication()
    app.launchEnvironment["REMOTE_LOCATION_E2E_SEARCH_FIXTURE"] = "1"
    app.launch()
    app.tap()

    openLocationPicker(in: app)
    app.buttons["use-map-center"].tap()
    app.buttons["close-location-picker"].tap()
    let previousLatitude = app.staticTexts["selected-latitude"].label
    let previousLongitude = app.staticTexts["selected-longitude"].label

    openLocationPicker(in: app)
    let field = app.textFields["place-search-input"]
    replaceText(in: field, with: "empty")
    app.buttons["search-places"].tap()
    let status = app.staticTexts["place-search-status"]
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    XCTAssertEqual(status.label, "No places found. Try a more specific query.")

    replaceText(in: field, with: "failure")
    app.buttons["search-places"].tap()
    XCTAssertTrue(
      status.waitForExistence(timeout: 5)
    )
    XCTAssertEqual(
      status.label,
      "Place search is unavailable. Check your network connection and try again; your previous selection is unchanged."
    )
    app.buttons["close-location-picker"].tap()

    XCTAssertTrue(app.staticTexts["selection-source"].label.hasSuffix("Map"))
    XCTAssertEqual(app.staticTexts["selected-latitude"].label, previousLatitude)
    XCTAssertEqual(app.staticTexts["selected-longitude"].label, previousLongitude)
  }

  func testPublicLocationBackendRemainsStableForTenMinutes() throws {
    if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
      throw XCTSkip("The ten-minute backend gate is recorded only on a physical device.")
    }

    let app = XCUIApplication()
    app.launch()
    app.tap()
    defer { XCUIDevice.shared.location = nil }

    let coordinateA = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    let coordinateB = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
    let minimumDuration: TimeInterval = 600
    let startedAt = Date()
    var completedRounds = 0

    repeat {
      applyAndVerify(coordinateA, in: app)
      applyAndVerify(coordinateB, in: app)
      clearAndVerifyProxyInactive(in: app)
      completedRounds += 1
      XCTContext.runActivity(named: "Completed public A/B/clear round \(completedRounds)") { _ in }
    } while Date().timeIntervalSince(startedAt) < minimumDuration

    let duration = Date().timeIntervalSince(startedAt)
    XCTAssertGreaterThanOrEqual(completedRounds, 2)
    XCTAssertGreaterThanOrEqual(duration, minimumDuration)
    XCTContext.runActivity(
      named:
        "Public location gate completed \(completedRounds) rounds in \(duration.formatted(.number.precision(.fractionLength(1)))) seconds"
    ) { _ in }
  }

  private func applyAndVerify(
    _ coordinate: CLLocationCoordinate2D,
    in app: XCUIApplication
  ) {
    selectAndBeginObservation(of: coordinate, in: app)

    verifyFreshObservation(of: coordinate, in: app)
  }

  private func verifyFreshObservation(
    of coordinate: CLLocationCoordinate2D,
    in app: XCUIApplication
  ) {
    let start = app.buttons["start-observation-window"]
    for _ in 0..<10 where !start.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()

    XCUIDevice.shared.location = XCUILocation(
      location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    )

    let status = app.staticTexts["match-status"]
    for _ in 0..<4 where !status.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
    let matched = app.staticTexts.matching(identifier: "match-status")
      .matching(NSPredicate(format: "label == %@", "GPX baseline matched"))
      .firstMatch
    XCTAssertTrue(matched.waitForExistence(timeout: 15))

    let observedTimestamp = app.staticTexts["observed-timestamp"]
    for _ in 0..<4 where !observedTimestamp.exists {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(observedTimestamp.waitForExistence(timeout: 5))
    let observedTimestampLabel = observedTimestamp.label

    let elapsed = app.staticTexts["match-elapsed"]
    let distance = app.staticTexts["match-distance"]
    for _ in 0..<4 where !elapsed.exists || !distance.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
    XCTAssertTrue(distance.waitForExistence(timeout: 5))
    XCTContext.runActivity(
      named:
        "Learning App verified fresh observation (\(observedTimestampLabel); \(elapsed.label); \(distance.label))"
    ) { _ in }
  }

  private func applyAndVerifySimulation(
    of coordinate: CLLocationCoordinate2D,
    in app: XCUIApplication
  ) {
    let apply = app.buttons["apply-selected-location"]
    scrollUp(until: apply, in: app)
    XCTAssertTrue(apply.waitForExistence(timeout: 5))
    XCTAssertTrue(apply.isEnabled)
    apply.tap()

    let applied = app.staticTexts.matching(identifier: "simulation-status")
      .matching(
        NSPredicate(
          format: "label == %@",
          "Applied Simulation — waiting for a fresh observation"
        )
      )
      .firstMatch
    XCTAssertTrue(applied.waitForExistence(timeout: 5))

    XCUIDevice.shared.location = XCUILocation(
      location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    )

    let verified = app.staticTexts.matching(identifier: "simulation-status")
      .matching(
        NSPredicate(
          format: "label == %@",
          "Verified Simulation in this Learning App"
        )
      )
      .firstMatch
    XCTAssertTrue(verified.waitForExistence(timeout: 15))
  }

  private func clearAndVerifyProxyInactive(in app: XCUIApplication) {
    XCUIDevice.shared.location = nil
    XCTAssertNil(
      XCUIDevice.shared.location,
      "The public XCUIDevice location getter still reports an active proxy after clear."
    )

    let recencyNote = app.staticTexts["observation-recency-note"]
    for _ in 0..<4 where !recencyNote.exists {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(recencyNote.waitForExistence(timeout: 5))
    XCTAssertEqual(
      recencyNote.label,
      "This is the last successful Core Location observation. It may remain after a simulation stops and does not indicate an active simulation."
    )
    XCTContext.runActivity(
      named: "Public location proxy cleared; Learning App retains only last-observation evidence"
    ) { _ in }
  }

  private func selectAndBeginObservation(
    of coordinate: CLLocationCoordinate2D,
    in app: XCUIApplication
  ) {
    scrollToTop(in: app)
    let latitude = app.textFields["latitude-input"]
    scrollUp(until: latitude, in: app)
    XCTAssertTrue(latitude.waitForExistence(timeout: 5))

    replaceText(
      in: latitude,
      with: String(format: "%.6f", coordinate.latitude)
    )
    replaceText(
      in: app.textFields["longitude-input"],
      with: String(format: "%.6f", coordinate.longitude)
    )
    app.buttons["Return"].tap()
    app.buttons["save-selection"].tap()

  }

  private func waitForObservedCoordinate(
    _ coordinate: CLLocationCoordinate2D,
    in app: XCUIApplication
  ) {
    let observedLatitude = app.staticTexts["observed-latitude"]
    scrollUp(until: observedLatitude, in: app)
    let expectedSuffix = String(format: "%.6f", coordinate.latitude)
    let matchingLatitude = app.staticTexts.matching(identifier: "observed-latitude")
      .matching(NSPredicate(format: "label ENDSWITH %@", expectedSuffix))
      .firstMatch
    XCTAssertTrue(matchingLatitude.waitForExistence(timeout: 10))
  }

  private func replaceText(in field: XCUIElement, with text: String) {
    field.tap()
    if let existing = field.value as? String {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    }
    field.typeText(text)
  }

  private func openLocationPicker(in app: XCUIApplication) {
    let button = app.buttons["open-location-picker"]
    for _ in 0..<5 where !button.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
  }

  private func waitForSelectionConfirmation(in app: XCUIApplication) {
    let confirmation = app.staticTexts["location-selection-confirmation"]
    for _ in 0..<4 where !confirmation.exists {
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
  }

  private func permissionFixtureApp(
    location: String,
    localNetwork: String
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["REMOTE_LOCATION_E2E_LOCATION_PERMISSION"] = location
    app.launchEnvironment["REMOTE_LOCATION_E2E_LOCAL_NETWORK_PERMISSION"] = localNetwork
    return app
  }

  private func scrollUp(until element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 where !element.exists {
      app.collectionViews.firstMatch.swipeUp()
    }
  }

  private func scrollToTop(in app: XCUIApplication) {
    for _ in 0..<6 {
      app.collectionViews.firstMatch.swipeDown()
    }
  }

  private func scrollUpInSmallSteps(until element: XCUIElement, in app: XCUIApplication) {
    let collectionView = app.collectionViews.firstMatch
    for _ in 0..<6 where !element.exists {
      let start = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
      let finish = collectionView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
      start.press(forDuration: 0.05, thenDragTo: finish)
    }
  }
}
