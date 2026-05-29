import SwiftUI

/// Floating search overlay. Matches the route planner card style: rounded
/// material panel anchored top-leading. Three tabs (Results / History /
/// Categories) under a live text field. Selecting a result hands off to the
/// engine which selects the place and centers the map; OMPlacePage then opens
/// the existing info pane.
struct SearchView: View {
  @ObservedObject var model: SearchModel
  let onDismiss: () -> Void
  let onResultSelected: () -> Void

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header

      Picker("", selection: $model.tab) {
        Text(resultsTabLabel).tag(SearchModel.Tab.results)
        Text("History").tag(SearchModel.Tab.history)
        Text("Categories").tag(SearchModel.Tab.categories)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if model.pinsLive {
        HStack(spacing: 6) {
          Image(systemName: "mappin.and.ellipse")
            .font(.caption).foregroundStyle(.tint)
          Text("Results pinned on map").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Clear pins") { model.clearMap() }
            .buttonStyle(.borderless)
            .font(.caption)
        }
      }

      Group {
        switch model.tab {
        case .results:    resultsList
        case .history:    historyList
        case .categories: categoriesList
        }
      }
      .frame(minHeight: 60, maxHeight: 340)
    }
    .padding(14)
    .frame(width: 380)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(radius: 8)
    .onAppear {
      model.refreshLists()
      focused = true
      if model.tab == .results && model.query.isEmpty {
        model.tab = model.history.isEmpty ? .categories : .history
      }
    }
  }

  private var resultsTabLabel: String {
    model.isSearching && model.results.isEmpty ? "Results …" : "Results"
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Search", text: $model.query)
        .textFieldStyle(.plain)
        .focused($focused)
        .onSubmit {
          // Enter drops pins for every current result onto the map; the
          // dialog stays open so the user can scan the list against the map.
          model.showAllOnMap()
        }
      if !model.query.isEmpty {
        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.borderless).foregroundStyle(.secondary)
      }
      Button { onDismiss() } label: { Image(systemName: "xmark") }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close search")
    }
  }

  // MARK: - Results tab

  @ViewBuilder private var resultsList: some View {
    if model.results.isEmpty {
      placeholder(
        icon: "magnifyingglass",
        text: model.query.isEmpty ? "Type to search" : (model.isSearching ? "Searching…" : "No matches"))
    } else {
      List(model.results, id: \.index) { r in
        Button { handle(r) } label: { resultRow(r) }
          .buttonStyle(.plain)
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
  }

  private func resultRow(_ r: OMSearchResult) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon(for: r))
        .frame(width: 22).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(r.title).lineLimit(1)
        if let s = r.subtitle, !s.isEmpty {
          Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if let a = r.address, !a.isEmpty {
          Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer()
    }
  }

  private func icon(for r: OMSearchResult) -> String {
    switch r.kind {
    case .suggestion: return "text.cursor"
    case .latLon:     return "mappin"
    case .postcode:   return "envelope"
    case .feature:    return "mappin.and.ellipse"
    @unknown default: return "mappin"
    }
  }

  private func handle(_ r: OMSearchResult) {
    model.select(r)
    if r.kind != .suggestion {
      onResultSelected()
    }
  }

  // MARK: - History tab

  @ViewBuilder private var historyList: some View {
    if model.history.isEmpty {
      placeholder(icon: "clock", text: "No recent searches")
    } else {
      VStack(spacing: 0) {
        List(model.history, id: \.self) { q in
          Button { model.runHistory(q) } label: {
            HStack(spacing: 10) {
              Image(systemName: "clock.arrow.circlepath")
                .frame(width: 22).foregroundStyle(.secondary)
              Text(q)
              Spacer()
            }
          }
          .buttonStyle(.plain)
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)

        HStack {
          Spacer()
          Button("Clear History", role: .destructive) { model.clearHistory() }
            .buttonStyle(.borderless)
        }.padding(.top, 4)
      }
    }
  }

  // MARK: - Categories tab

  private var categoriesList: some View {
    List(model.categories, id: \.self) { key in
      Button { model.runCategory(key) } label: {
        HStack(spacing: 10) {
          Image(systemName: categoryIcon(key))
            .frame(width: 22).foregroundStyle(.tint)
          Text(categoryTitle(key))
          Spacer()
        }
      }
      .buttonStyle(.plain)
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  // MARK: - Helpers

  private func placeholder(icon: String, text: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.secondary)
      Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 24)
  }

  /// Best-effort category labelling. Engine keys are localization keys
  /// (e.g. "food", "transport"); until the macOS app bundles strings.txt we
  /// title-case the key as a passable English label.
  private func categoryTitle(_ key: String) -> String {
    let cleaned = key.replacingOccurrences(of: "_", with: " ")
    return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
  }

  /// Map common OSM category keys to SF Symbols. Falls back to a generic icon.
  private func categoryIcon(_ key: String) -> String {
    switch key {
    case "food", "eat", "restaurant":          return "fork.knife"
    case "drink", "bar", "cafe":               return "cup.and.saucer"
    case "transport":                          return "tram.fill"
    case "fuel":                               return "fuelpump"
    case "parking":                            return "parkingsign"
    case "shopping", "shop", "clothes", "secondhand": return "bag"
    case "hotel":                              return "bed.double"
    case "tourism":                            return "camera"
    case "entertainment":                      return "theatermasks"
    case "nightlife":                          return "moon.stars"
    case "children":                           return "figure.and.child.holdinghands"
    case "atm":                                return "creditcard"
    case "bank":                               return "building.columns"
    case "hospital":                           return "cross.case"
    case "pharmacy":                           return "pills"
    case "post":                               return "envelope"
    case "toilet":                             return "toilet"
    case "police":                             return "shield"
    case "water", "waterbody":                 return "drop"
    case "wifi":                               return "wifi"
    case "charging_station":                   return "bolt.car"
    case "airport":                            return "airplane"
    case "mountain":                           return "mountain.2"
    case "recycling":                          return "arrow.3.trianglepath"
    case "rv":                                 return "bus"
    case "gambling":                           return "suit.club"
    default:                                   return "mappin.and.ellipse"
    }
  }
}
