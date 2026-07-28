import XCTest

@testable import LocationDomain

final class SelectedLocationTests: XCTestCase {
  func testAcceptsWGS84BoundaryCoordinates() throws {
    let southwest = try SelectedLocation(latitude: -90, longitude: -180)
    let northeast = try SelectedLocation(latitude: 90, longitude: 180)

    XCTAssertEqual(southwest.latitude, -90)
    XCTAssertEqual(southwest.longitude, -180)
    XCTAssertEqual(northeast.latitude, 90)
    XCTAssertEqual(northeast.longitude, 180)
  }

  func testRejectsCoordinatesOutsideWGS84() {
    let invalidCoordinates = [
      (latitude: -90.000_001, longitude: 0.0),
      (latitude: 90.000_001, longitude: 0.0),
      (latitude: 0.0, longitude: -180.000_001),
      (latitude: 0.0, longitude: 180.000_001),
    ]

    for coordinate in invalidCoordinates {
      XCTAssertThrowsError(
        try SelectedLocation(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude
        )
      ) { error in
        XCTAssertTrue(error is LocationInputError)
      }
    }
  }

  func testParsesDecimalTextWithoutChangingTheSelectedCoordinate() throws {
    let selection = try SelectedLocation.parse(
      latitude: " 31.2304 ",
      longitude: "121.4737"
    )

    XCTAssertEqual(
      selection,
      try SelectedLocation(latitude: 31.2304, longitude: 121.4737)
    )
  }

  func testRejectsInvalidCoordinateText() {
    let invalidInputs = [
      (latitude: "", longitude: "121.4737"),
      (latitude: "north", longitude: "121.4737"),
      (latitude: "31.2304", longitude: "east"),
    ]

    for input in invalidInputs {
      XCTAssertThrowsError(
        try SelectedLocation.parse(
          latitude: input.latitude,
          longitude: input.longitude
        )
      ) { error in
        XCTAssertTrue(error is LocationInputError)
      }
    }
  }
}
