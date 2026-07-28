public enum LocationSelectionSource: String, Equatable, Sendable {
  case manual
  case map
  case search
}

public struct LocationSelectionState: Equatable, Sendable {
  public private(set) var selected: SelectedLocation?
  public private(set) var source: LocationSelectionSource?

  public init() {}

  public mutating func select(
    _ location: SelectedLocation,
    source: LocationSelectionSource
  ) {
    selected = location
    self.source = source
  }
}
