import XCTest

@testable import LocationDomain

final class LocationDistanceTests: XCTestCase {
  func testReturnsZeroForTheSameCoordinate() throws {
    let location = try SelectedLocation(latitude: 31.2304, longitude: 121.4737)

    XCTAssertEqual(LocationDistance.meters(from: location, to: location), 0, accuracy: 0.001)
  }

  func testMeasuresRepresentativeCloseAdjustmentDistances() throws {
    let origin = try SelectedLocation(latitude: 31.2304, longitude: 121.4737)
    let locations = [
      (try SelectedLocation(latitude: 31.2304899322, longitude: 121.4737), 10.0),
      (try SelectedLocation(latitude: 31.2312993216, longitude: 121.4737), 100.0),
      (try SelectedLocation(latitude: 31.2348966080, longitude: 121.4737), 500.0),
    ]

    for (location, expectedMeters) in locations {
      XCTAssertEqual(
        LocationDistance.meters(from: origin, to: location),
        expectedMeters,
        accuracy: expectedMeters * 0.01
      )
    }
  }

  func testMeasuresDistanceWithNegativeCoordinates() throws {
    let origin = try SelectedLocation(latitude: -33.8688, longitude: -151.2093)
    let moved = try SelectedLocation(latitude: -33.8696993216, longitude: -151.2093)

    XCTAssertEqual(
      LocationDistance.meters(from: origin, to: moved),
      100,
      accuracy: 1
    )
  }

  func testLongitudeDistanceShrinksAwayFromTheEquator() throws {
    let equatorOrigin = try SelectedLocation(latitude: 0, longitude: 0)
    let equatorMoved = try SelectedLocation(latitude: 0, longitude: 0.0008993216)
    let highLatitudeOrigin = try SelectedLocation(latitude: 60, longitude: 0)
    let highLatitudeMoved = try SelectedLocation(latitude: 60, longitude: 0.0008993216)

    let equatorDistance = LocationDistance.meters(
      from: equatorOrigin,
      to: equatorMoved
    )
    let highLatitudeDistance = LocationDistance.meters(
      from: highLatitudeOrigin,
      to: highLatitudeMoved
    )

    XCTAssertEqual(equatorDistance, 100, accuracy: 1)
    XCTAssertEqual(highLatitudeDistance, 50, accuracy: 1)
    XCTAssertLessThan(highLatitudeDistance, equatorDistance)
  }
}
