import Foundation
import XCTest

@testable import LocationDomain

final class ObservationMatcherTests: XCTestCase {
  private let requestTime = Date(timeIntervalSince1970: 1_000)
  private let selected = try! SelectedLocation(latitude: 31.2304, longitude: 121.4737)

  func testMatchesFreshObservationWithinTwentyFiveMeters() throws {
    let observation = try observation(
      latitude: 31.2304,
      longitude: 121.4737,
      secondsAfterRequest: 10,
      isSimulatedBySoftware: true
    )

    guard
      case .matched(let evidence) = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: observation
      )
    else {
      return XCTFail("Expected a matched observation")
    }

    XCTAssertEqual(evidence.elapsedSeconds, 10)
    XCTAssertEqual(evidence.distanceMeters, 0, accuracy: 0.001)
  }

  func testRequiresObservationTimestampToBeAfterRequest() throws {
    let observation = try observation(secondsAfterRequest: 0)

    XCTAssertEqual(
      ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: observation
      ),
      .notAfterRequest
    )
  }

  func testAcceptsObservationAtFifteenSecondBoundary() throws {
    let observation = try observation(secondsAfterRequest: 15)

    guard
      case .matched = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: observation
      )
    else {
      return XCTFail("Expected the 15-second boundary to match")
    }
  }

  func testRejectsObservationAfterFifteenSecondWindow() throws {
    let observation = try observation(secondsAfterRequest: 15.001)

    guard
      case .timedOut(let elapsedSeconds) = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: observation
      )
    else {
      return XCTFail("Expected observation timeout")
    }

    XCTAssertEqual(elapsedSeconds, 15.001, accuracy: 0.000_1)
  }

  func testAcceptsApproximatelyTwentyFourMetersAndRejectsApproximatelyTwentySix() throws {
    let nearObservation = try observation(
      latitude: 31.2304,
      longitude: 121.47395,
      secondsAfterRequest: 5
    )
    let farObservation = try observation(
      latitude: 31.2304,
      longitude: 121.47398,
      secondsAfterRequest: 5
    )

    guard
      case .matched = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: nearObservation
      )
    else {
      return XCTFail("Expected the near observation to match")
    }
    guard
      case .tooFar(let distanceMeters) = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: farObservation
      )
    else {
      return XCTFail("Expected the far observation to be rejected")
    }

    XCTAssertGreaterThan(distanceMeters, 25)
  }

  func testSimulationSourceFlagDoesNotDecideMatching() throws {
    let sourceValues: [Bool?] = [true, false, nil]

    for sourceValue in sourceValues {
      let observation = try observation(
        secondsAfterRequest: 5,
        isSimulatedBySoftware: sourceValue
      )

      guard
        case .matched = ObservationMatcher.evaluate(
          selected: selected,
          requestedAt: requestTime,
          observation: observation
        )
      else {
        return XCTFail(
          "Expected source value \(String(describing: sourceValue)) to be diagnostic only")
      }
    }
  }

  func testHorizontalAccuracyIsDiagnosticOnly() throws {
    let observation = try observation(
      secondsAfterRequest: 5,
      horizontalAccuracy: 500
    )

    guard
      case .matched = ObservationMatcher.evaluate(
        selected: selected,
        requestedAt: requestTime,
        observation: observation
      )
    else {
      return XCTFail("Expected horizontal accuracy to remain diagnostic")
    }
  }

  private func observation(
    latitude: Double = 31.2304,
    longitude: Double = 121.4737,
    secondsAfterRequest: TimeInterval,
    horizontalAccuracy: Double = 5,
    isSimulatedBySoftware: Bool? = nil
  ) throws -> LocationObservation {
    LocationObservation(
      coordinate: try SelectedLocation(latitude: latitude, longitude: longitude),
      timestamp: requestTime.addingTimeInterval(secondsAfterRequest),
      horizontalAccuracy: horizontalAccuracy,
      isSimulatedBySoftware: isSimulatedBySoftware
    )
  }
}
