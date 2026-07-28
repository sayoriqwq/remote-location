import XCTest

@testable import LocationDomain

final class LocationSelectionStateTests: XCTestCase {
  func testManualMapAndSearchReplaceOneSharedSelectedLocation() throws {
    let manual = try SelectedLocation(latitude: 31.2304, longitude: 121.4737)
    let map = try SelectedLocation(latitude: 52.52, longitude: 13.405)
    let search = try SelectedLocation(latitude: 35.6762, longitude: 139.6503)
    var state = LocationSelectionState()

    state.select(manual, source: .manual)
    XCTAssertEqual(state.selected, manual)
    XCTAssertEqual(state.source, .manual)

    state.select(map, source: .map)
    XCTAssertEqual(state.selected, map)
    XCTAssertEqual(state.source, .map)

    state.select(search, source: .search)
    XCTAssertEqual(state.selected, search)
    XCTAssertEqual(state.source, .search)
  }
}
