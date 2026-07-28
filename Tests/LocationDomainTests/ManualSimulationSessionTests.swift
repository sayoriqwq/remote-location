import XCTest

@testable import LocationDomain

final class ManualSimulationSessionTests: XCTestCase {
  private let location = try! SelectedLocation(latitude: 31.2304, longitude: 121.4737)
  private let requestTime = Date(timeIntervalSince1970: 1_000)

  func testOnlyAppliedRequestCanBecomeVerifiedByAFreshNearbyObservation() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let requestID = UUID()
    let request = try session.beginApply(requestID: requestID, at: requestTime)

    session.record(observation(secondsAfterRequest: 2))
    XCTAssertEqual(session.status, .applying(request))

    XCTAssertTrue(session.acknowledgeApplied(requestID: requestID))
    XCTAssertEqual(session.status, .applied(request))

    session.record(observation(secondsAfterRequest: 3))
    guard case .verified(let verifiedRequest, let evidence) = session.status else {
      return XCTFail("Expected the current Applied request to become Verified")
    }
    XCTAssertEqual(verifiedRequest, request)
    XCTAssertEqual(evidence.elapsedSeconds, 3)
    XCTAssertEqual(evidence.distanceMeters, 0, accuracy: 0.001)
  }

  func testNewApplyImmediatelyInvalidatesEarlierVerification() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let firstID = UUID()
    _ = try session.beginApply(requestID: firstID, at: requestTime)
    _ = session.acknowledgeApplied(requestID: firstID)
    session.record(observation(secondsAfterRequest: 2))
    guard case .verified = session.status else {
      return XCTFail("Expected initial verification")
    }

    let secondID = UUID()
    let secondRequest = try session.beginApply(
      requestID: secondID,
      at: requestTime.addingTimeInterval(10)
    )

    XCTAssertEqual(session.status, .applying(secondRequest))
  }

  func testWrongAcknowledgementIdentityFailsWithoutClaimingApplied() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let requestID = UUID()
    let request = try session.beginApply(requestID: requestID, at: requestTime)

    XCTAssertFalse(session.acknowledgeApplied(requestID: UUID()))
    XCTAssertEqual(session.status, .failed(request, .responseIdentityMismatch))
  }

  func testAppliedRequestRetainsActionableDistanceAndTimeoutDiagnostics() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let requestID = UUID()
    let request = try session.beginApply(requestID: requestID, at: requestTime)
    _ = session.acknowledgeApplied(requestID: requestID)

    session.record(
      LocationObservation(
        coordinate: try SelectedLocation(latitude: 31.2304, longitude: 121.4741),
        timestamp: requestTime.addingTimeInterval(3),
        horizontalAccuracy: 5,
        isSimulatedBySoftware: true
      )
    )
    guard case .appliedNotVerified(let currentRequest, .tooFar(let meters)) = session.status else {
      return XCTFail("Expected an Applied-but-not-verified distance diagnostic")
    }
    XCTAssertEqual(currentRequest, request)
    XCTAssertGreaterThan(meters, 25)

    session.expire(at: requestTime.addingTimeInterval(15.001))
    guard
      case .appliedNotVerified(
        let timedOutRequest,
        .timedOut(let elapsedSeconds)
      ) = session.status
    else {
      return XCTFail("Expected an Applied-but-not-verified timeout diagnostic")
    }
    XCTAssertEqual(timedOutRequest, request)
    XCTAssertEqual(elapsedSeconds, 15.001, accuracy: 0.000_1)
  }

  func testStopClearsTheActiveAppliedRequestOnlyAfterMatchingAcknowledgement() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let applyID = UUID()
    let appliedRequest = try session.beginApply(requestID: applyID, at: requestTime)
    XCTAssertTrue(session.acknowledgeApplied(requestID: applyID))
    XCTAssertEqual(session.activeAppliedRequest, appliedRequest)

    let stopID = UUID()
    session.beginStop(requestID: stopID)
    XCTAssertFalse(session.acknowledgeStopped(requestID: UUID()))
    XCTAssertEqual(session.activeAppliedRequest, appliedRequest)
    guard case .failed(let failedID, .responseIdentityMismatch) = session.stopStatus else {
      return XCTFail("Expected a correlated Stop failure")
    }
    XCTAssertEqual(failedID, stopID)

    session.beginStop(requestID: stopID)
    XCTAssertTrue(session.acknowledgeStopped(requestID: stopID))
    XCTAssertNil(session.activeAppliedRequest)
    XCTAssertEqual(session.stopStatus, .stopped(requestID: stopID))
    XCTAssertEqual(session.status, .stopped)
  }

  func testFailedReplacementKeepsThePreviouslyAppliedSimulationActive() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let firstID = UUID()
    let firstRequest = try session.beginApply(requestID: firstID, at: requestTime)
    _ = session.acknowledgeApplied(requestID: firstID)

    try session.select(latitude: "52.5200", longitude: "13.4050")
    let secondID = UUID()
    _ = try session.beginApply(
      requestID: secondID,
      at: requestTime.addingTimeInterval(10)
    )
    _ = session.fail(
      requestID: secondID,
      reason: .requestRejected(stableCode: "backendUnavailable")
    )

    XCTAssertEqual(session.activeAppliedRequest, firstRequest)
  }

  func testLateAppliedAcknowledgementStillEndsAsAppliedButTimedOut() throws {
    var session = ManualSimulationSession()
    try session.select(latitude: "31.2304", longitude: "121.4737")
    let requestID = UUID()
    let request = try session.beginApply(requestID: requestID, at: requestTime)

    session.expire(at: requestTime.addingTimeInterval(15.001))
    XCTAssertEqual(session.status, .applying(request))
    XCTAssertTrue(session.acknowledgeApplied(requestID: requestID))
    session.expire(at: requestTime.addingTimeInterval(16))

    XCTAssertEqual(
      session.status,
      .appliedNotVerified(request, .timedOut(elapsedSeconds: 16))
    )
  }

  private func observation(secondsAfterRequest: TimeInterval) -> LocationObservation {
    LocationObservation(
      coordinate: location,
      timestamp: requestTime.addingTimeInterval(secondsAfterRequest),
      horizontalAccuracy: 5,
      isSimulatedBySoftware: true
    )
  }
}
