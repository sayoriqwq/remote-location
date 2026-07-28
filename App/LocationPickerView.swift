import Foundation
import MapKit
import SwiftUI

@MainActor
struct LocationPickerView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var searchModel: LocationPickerViewModel
  @State private var cameraPosition: MapCameraPosition
  @State private var mapCenter: CLLocationCoordinate2D
  @State private var selectionConfirmation: String?
  @State private var selectionFailure: String?
  @FocusState private var searchFieldFocused: Bool

  let selected: SelectedLocation?
  let onSelect: (SelectedLocation, LocationSelectionSource) -> Bool

  init(
    selected: SelectedLocation?,
    onSelect: @escaping (SelectedLocation, LocationSelectionSource) -> Bool
  ) {
    self.selected = selected
    self.onSelect = onSelect

    let center = CLLocationCoordinate2D(
      latitude: selected?.latitude ?? 31.2304,
      longitude: selected?.longitude ?? 121.4737
    )
    _mapCenter = State(initialValue: center)
    _cameraPosition = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: center,
          span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
      )
    )

    let searcher: any LocationSearching
    #if DEBUG
      if ProcessInfo.processInfo.environment[
        "REMOTE_LOCATION_E2E_SEARCH_FIXTURE"
      ] == "1" {
        searcher = FixtureLocationSearcher()
      } else {
        searcher = MapKitLocationSearcher()
      }
    #else
      searcher = MapKitLocationSearcher()
    #endif
    _searchModel = StateObject(
      wrappedValue: LocationPickerViewModel(searcher: searcher)
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          mapSection
          searchSection

          Text(
            "Choosing here only replaces the current Selected Location. It never applies a simulation until you use Apply Selected Location."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)

          if let selectionConfirmation {
            Label(selectionConfirmation, systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .accessibilityIdentifier("location-selection-confirmation")
          }
          if let selectionFailure {
            Label(selectionFailure, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .accessibilityIdentifier("location-selection-failure")
          }
        }
        .padding()
      }
      .navigationTitle("Choose Location")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("close-location-picker")
        }
      }
    }
  }

  private var mapSection: some View {
    GroupBox("Map") {
      VStack(alignment: .leading, spacing: 12) {
        Map(position: $cameraPosition) {
          if let selected {
            Marker(
              "Selected",
              coordinate: CLLocationCoordinate2D(
                latitude: selected.latitude,
                longitude: selected.longitude
              )
            )
          }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          Image(systemName: "plus")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(8)
            .background(.thinMaterial, in: Circle())
            .allowsHitTesting(false)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
          mapCenter = context.region.center
        }
        .accessibilityIdentifier("location-map")

        LabeledContent("Map center") {
          Text(
            "\(mapCenter.latitude.formatted(.number.precision(.fractionLength(6)))), \(mapCenter.longitude.formatted(.number.precision(.fractionLength(6))))"
          )
          .font(.footnote.monospacedDigit())
          .accessibilityIdentifier("map-center-coordinate")
        }

        Button("Use Map Center as Selected Location") {
          guard
            let location = try? SelectedLocation(
              latitude: mapCenter.latitude,
              longitude: mapCenter.longitude
            )
          else { return }
          commit(
            location,
            source: .map,
            confirmation: "Map center is now the Selected Location."
          )
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("use-map-center")
      }
      .padding(.top, 8)
    }
  }

  private var searchSection: some View {
    GroupBox("Place Search") {
      VStack(alignment: .leading, spacing: 12) {
        TextField("Search for a place", text: $searchModel.query)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .focused($searchFieldFocused)
          .onSubmit {
            searchFieldFocused = false
            searchModel.search()
          }
          .accessibilityIdentifier("place-search-input")

        Button("Search Places") {
          searchFieldFocused = false
          searchModel.search()
        }
        .disabled(!searchModel.canSearch)
        .accessibilityIdentifier("search-places")

        searchResults
      }
      .padding(.top, 8)
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    switch searchModel.status {
    case .idle:
      Text("Enter a place name or address.")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("place-search-status")
    case .searching:
      HStack {
        ProgressView()
        Text("Searching…")
      }
      .accessibilityIdentifier("place-search-status")
    case .empty:
      Label("No places found. Try a more specific query.", systemImage: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("place-search-status")
    case .failed:
      Label(
        "Place search is unavailable. Check your network connection and try again; your previous selection is unchanged.",
        systemImage: "wifi.exclamationmark"
      )
      .foregroundStyle(.red)
      .accessibilityIdentifier("place-search-status")
    case .results(let results):
      ForEach(results) { result in
        Button {
          commit(
            result.location,
            source: .search,
            confirmation: "\(result.name) is now the Selected Location."
          )
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(result.name)
              .foregroundStyle(.primary)
            if let detail = result.detail {
              Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .accessibilityIdentifier("place-search-result")
      }
    }
  }

  private func commit(
    _ location: SelectedLocation,
    source: LocationSelectionSource,
    confirmation: String
  ) {
    if onSelect(location, source) {
      selectionConfirmation = confirmation
      selectionFailure = nil
    } else {
      selectionConfirmation = nil
      selectionFailure = "Finish the current apply or stop request before changing the selection."
    }
  }
}
