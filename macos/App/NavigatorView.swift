import SwiftUI

/// Left slide-over pane: a flat list of bookmark lists, each expandable to its
/// bookmarks and tracks. Selecting an item drives the right-hand info pane.
struct NavigatorView: View {
  @ObservedObject var model: BookmarksNavigatorModel
  let onSelectList: (BookmarkGroup) -> Void
  let onSelectBookmark: (MWMMarkID) -> Void
  let onSelectTrack: (MWMTrackID) -> Void
  let onHide: () -> Void

  enum ListSort: String, CaseIterable, Identifiable {
    case dateAdded = "Date Added", nameAsc = "Name A→Z", nameDesc = "Name Z→A"
    var id: String { rawValue }
  }
  enum ItemSort: String, CaseIterable, Identifiable {
    case nameAsc = "Name A→Z", nameDesc = "Name Z→A", distanceLength = "Distance / Length"
    var id: String { rawValue }
  }

  private enum NavItem: Identifiable {
    case bookmark(Bookmark)
    case track(Track)
    var id: String {
      switch self {
      case .bookmark(let b): return "b\(b.bookmarkId)"
      case .track(let t): return "t\(t.trackId)"
      }
    }
    var name: String {
      switch self {
      case .bookmark(let b): return b.bookmarkName
      case .track(let t): return t.trackName
      }
    }
  }

  @State private var expanded: Set<MWMMarkGroupID> = []
  @State private var showNewList = false
  @State private var newListName = ""
  @State private var searchText = ""
  @State private var listSort: ListSort = .dateAdded
  @State private var itemSort: ItemSort = .nameAsc
  @State private var groupByType = true

  private var searching: Bool { !searchText.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      header
      searchField
      Divider()
      List {
        ForEach(visibleLists, id: \.categoryId) { list in
          listRow(list)
          if isExpanded(list) {
            listContent(list)
          }
        }
      }
      .listStyle(.sidebar)
    }
    .frame(width: 300)
    .background(.regularMaterial)
    .alert("New List", isPresented: $showNewList) {
      TextField("Name", text: $newListName)
      Button("Create") { model.createList(newListName); newListName = "" }
      Button("Cancel", role: .cancel) { newListName = "" }
    }
  }

  @ViewBuilder private func listContent(_ list: BookmarkGroup) -> some View {
    let bookmarks = bookmarksToShow(list)
    let tracks = tracksToShow(list)
    if groupByType {
      if !bookmarks.isEmpty {
        sectionLabel("Bookmarks")
        ForEach(bookmarks, id: \.bookmarkId) { bookmarkRow($0) }
      }
      if !tracks.isEmpty {
        sectionLabel("Tracks")
        ForEach(tracks, id: \.trackId) { trackRow($0) }
      }
    } else {
      ForEach(mixed(bookmarks, tracks)) { item in
        switch item {
        case .bookmark(let b): bookmarkRow(b)
        case .track(let t): trackRow(t)
        }
      }
    }
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
      .padding(.leading, 18).padding(.top, 4)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Bookmarks").font(.headline)
      Spacer()
      Menu {
        Section("Sort Lists") {
          Picker("Lists", selection: $listSort) {
            ForEach(ListSort.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.inline)
        }
        Section("Sort Items") {
          Picker("Items", selection: $itemSort) {
            ForEach(ItemSort.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.inline)
        }
        Toggle("Group by type", isOn: $groupByType)
      } label: {
        Image(systemName: "arrow.up.arrow.down")
      }
      .menuStyle(.borderlessButton).fixedSize().help("Sort")
      Button { showNewList = true } label: { Image(systemName: "plus") }
        .buttonStyle(.borderless).help("New list")
      Button { model.showAll() } label: { Image(systemName: "eye") }
        .buttonStyle(.borderless).help("Show all lists")
      Button { model.hideAll() } label: { Image(systemName: "eye.slash") }
        .buttonStyle(.borderless).help("Hide all lists")
      Button(action: onHide) { Image(systemName: "sidebar.left") }
        .buttonStyle(.borderless).help("Hide navigator")
    }
    .padding(16)
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Search lists, bookmarks, tracks", text: $searchText)
        .textFieldStyle(.plain)
      if searching {
        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.borderless).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  // MARK: - Sorting & filtering

  private func isExpanded(_ list: BookmarkGroup) -> Bool {
    searching || expanded.contains(list.categoryId)
  }

  private func listMatches(_ list: BookmarkGroup) -> Bool {
    list.title.localizedCaseInsensitiveContains(searchText)
  }

  private var visibleLists: [BookmarkGroup] {
    var lists = model.lists
    if searching {
      lists = lists.filter { listMatches($0) || !matchingBookmarks($0).isEmpty || !matchingTracks($0).isEmpty }
    }
    switch listSort {
    case .dateAdded: return lists
    case .nameAsc: return lists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    case .nameDesc: return lists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
    }
  }

  private func matchingBookmarks(_ list: BookmarkGroup) -> [Bookmark] {
    list.bookmarks.filter { $0.bookmarkName.localizedCaseInsensitiveContains(searchText) }
  }
  private func matchingTracks(_ list: BookmarkGroup) -> [Track] {
    list.tracks.filter { $0.trackName.localizedCaseInsensitiveContains(searchText) }
  }

  // When a list's own name matches, show all its items; otherwise only matches.
  private func bookmarksToShow(_ list: BookmarkGroup) -> [Bookmark] {
    let base = (searching && !listMatches(list)) ? matchingBookmarks(list) : list.bookmarks
    return sortBookmarks(base)
  }
  private func tracksToShow(_ list: BookmarkGroup) -> [Track] {
    let base = (searching && !listMatches(list)) ? matchingTracks(list) : list.tracks
    return sortTracks(base)
  }

  private func sortBookmarks(_ bookmarks: [Bookmark]) -> [Bookmark] {
    switch itemSort {
    case .nameAsc: return bookmarks.sorted { $0.bookmarkName.localizedCaseInsensitiveCompare($1.bookmarkName) == .orderedAscending }
    case .nameDesc: return bookmarks.sorted { $0.bookmarkName.localizedCaseInsensitiveCompare($1.bookmarkName) == .orderedDescending }
    case .distanceLength: return bookmarks.sorted { distance($0) < distance($1) }
    }
  }
  private func sortTracks(_ tracks: [Track]) -> [Track] {
    switch itemSort {
    case .nameAsc: return tracks.sorted { $0.trackName.localizedCaseInsensitiveCompare($1.trackName) == .orderedAscending }
    case .nameDesc: return tracks.sorted { $0.trackName.localizedCaseInsensitiveCompare($1.trackName) == .orderedDescending }
    case .distanceLength: return tracks.sorted { $0.trackLengthMeters < $1.trackLengthMeters }
    }
  }

  private func distance(_ bm: Bookmark) -> Double {
    let m = OMBookmarksHelper.metersFromCurrentPosition(toLat: bm.locationCoordinate.latitude,
                                                        lon: bm.locationCoordinate.longitude)
    return m < 0 ? .greatestFiniteMagnitude : m
  }

  // Undivided mixing sorts by name; distance/length aren't comparable across types.
  private func mixed(_ bookmarks: [Bookmark], _ tracks: [Track]) -> [NavItem] {
    let items = bookmarks.map { NavItem.bookmark($0) } + tracks.map { NavItem.track($0) }
    let ascending = itemSort != .nameDesc
    return items.sorted {
      let cmp = $0.name.localizedCaseInsensitiveCompare($1.name)
      return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
    }
  }

  private func listRow(_ list: BookmarkGroup) -> some View {
    HStack(spacing: 6) {
      Button { toggle(list.categoryId) } label: {
        Image(systemName: expanded.contains(list.categoryId) ? "chevron.down" : "chevron.right")
          .frame(width: 12)
      }
      .buttonStyle(.borderless)

      Button { onSelectList(list) } label: {
        HStack {
          Text(list.title).fontWeight(.medium)
          Spacer()
          Text("\(list.bookmarksCount + list.trackCount)")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)

      Button { model.setVisible(list, !list.isVisible) } label: {
        Image(systemName: list.isVisible ? "eye" : "eye.slash").foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
    }
    .contextMenu {
      Button("Delete List", role: .destructive) { model.deleteList(list.categoryId) }
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteList(list.categoryId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  @ViewBuilder private func moveMenu(_ action: @escaping (MWMMarkGroupID) -> Void) -> some View {
    Menu("Move to") {
      ForEach(model.lists, id: \.categoryId) { list in
        Button(list.title) { action(list.categoryId) }
      }
    }
  }

  private func bookmarkRow(_ bm: Bookmark) -> some View {
    Button { onSelectBookmark(bm.bookmarkId) } label: {
      HStack(spacing: 8) {
        Circle().fill(bm.bookmarkColor.swiftUIColor).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 1) {
          Text(bm.bookmarkName)
          if let sub = bookmarkSubtitle(bm) {
            Text(sub).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding(.leading, 18)
    }
    .buttonStyle(.plain)
    .contextMenu {
      moveMenu { model.moveBookmark(bm.bookmarkId, to: $0) }
      Button("Delete", role: .destructive) { model.deleteBookmark(bm.bookmarkId) }
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteBookmark(bm.bookmarkId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  private func trackRow(_ track: Track) -> some View {
    Button { onSelectTrack(track.trackId) } label: {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 1)
          .fill(Color(nsColor: track.trackColor)).frame(width: 12, height: 3)
        VStack(alignment: .leading, spacing: 1) {
          Text(track.trackName)
          Text(OMBookmarksHelper.formatDistance(meters: Double(track.trackLengthMeters)))
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.leading, 18)
    }
    .buttonStyle(.plain)
    .contextMenu {
      moveMenu { model.moveTrack(track.trackId, to: $0) }
      Button("Delete", role: .destructive) { model.deleteTrack(track.trackId) }
    }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteTrack(track.trackId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  private func bookmarkSubtitle(_ bm: Bookmark) -> String? {
    let coord = bm.locationCoordinate
    let distance = OMBookmarksHelper.distanceFromCurrentPosition(toLat: coord.latitude, lon: coord.longitude)
    // (NS_SWIFT_NAME pins this name)
    let type = bm.bookmarkType
    switch (type, distance) {
    case let (t?, d?) where !t.isEmpty: return "\(t) · \(d)"
    case let (_, d?): return d
    case let (t?, nil) where !t.isEmpty: return t
    default: return nil
    }
  }

  private func toggle(_ id: MWMMarkGroupID) {
    if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
  }
}
