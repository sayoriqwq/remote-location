import Foundation
import XCTest

@testable import LocationDomain

final class GPXBaselineSessionTests: XCTestCase {
  func testNewValidSelectionReplacesTheOnlySelectedLocation() throws {
    var session = GPXBaselineSession()

    try session.select(latitude: "31.2304", longitude: "121.4737")
    try session.select(latitude: "39.9042", longitude: "116.4074")

    XCTAssertEqual(
      session.selected,
      try SelectedLocation(latitude: 39.9042, longitude: 116.4074)
    )
  }

  func testInvalidInputDoesNotReplaceSelectionOrStartObservationWindow() throws {
    var session = GPXBaselineSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let originalSelection = session.selected

    XCTAssertThrowsError(
      try session.select(latitude: "91", longitude: "121.4737")
    )

    XCTAssertEqual(session.selected, originalSelection)
    XCTAssertNil(session.requestedAt)
  }

  func testNewSelectionInvalidatesPreviousObservationMatch() throws {
    var session = GPXBaselineSession()
    let requestTime = Date(timeIntervalSince1970: 1_000)
    try session.select(latitude: "31.2304", longitude: "121.4737")
    try session.beginObservationWindow(at: requestTime)
    session.record(
      LocationObservation(
        coordinate: try SelectedLocation(latitude: 31.2304, longitude: 121.4737),
        timestamp: requestTime.addingTimeInterval(5),
        horizontalAccuracy: 5,
        isSimulatedBySoftware: true
      )
    )
    guard case .matched = session.match else {
      return XCTFail("Expected initial selection to match")
    }

    try session.select(latitude: "39.9042", longitude: "116.4074")

    XCTAssertNil(session.requestedAt)
    XCTAssertNil(session.match)
  }

  func testObservationWindowRequiresSelection() {
    var session = GPXBaselineSession()

    XCTAssertThrowsError(
      try session.beginObservationWindow(at: Date())
    ) { error in
      XCTAssertEqual(error as? GPXBaselineSessionError, .noSelectedLocation)
    }
  }

  func testObservationWindowExpiresWhenNoFreshObservationArrives() throws {
    var session = GPXBaselineSession()
    let requestTime = Date(timeIntervalSince1970: 1_000)
    try session.select(latitude: "31.2304", longitude: "121.4737")
    try session.beginObservationWindow(at: requestTime)

    session.expireObservationWindow(
      at: requestTime.addingTimeInterval(15.001)
    )

    guard case .timedOut(let elapsedSeconds) = session.match else {
      return XCTFail("Expected an explicit timeout without a new observation")
    }
    XCTAssertEqual(elapsedSeconds, 15.001, accuracy: 0.000_1)
  }
}
