import AppKit
import SwiftUI

/// Left slide-over pane: a flat list of bookmark lists, each expandable to its
/// bookmarks and tracks. Plain click drives the right-hand info pane via the
/// engine; Cmd/Shift-click extend a parallel multi-selection that the bulk
/// context menu and multi-selection inspector consume.
struct NavigatorView: View {
  @ObservedObject var model: BookmarksNavigatorModel
  @ObservedObject var selection: NavigatorSelectionModel
  @ObservedObject var tagStore: TagStore
  @ObservedObject var projectsModel: ProjectModel
  let onSelectList: (BookmarkGroup) -> Void
  let onSelectBookmark: (MWMMarkID) -> Void
  let onSelectTrack: (MWMTrackID) -> Void
  let onHide: () -> Void

  /// Monotonic counter incremented by ContentView when the "Find in Library"
  /// menu command fires. Changes are observed here to focus the search field.
  /// A counter (not a Bool) so a second press while focused still re-focuses.
  let focusSearchRequest: Int

  @ObservedObject private var savedFilters = SavedFiltersStore.shared
  @Environment(\.openWindow) private var openWindow
  @State private var expandSmartFilters: Bool = true
  @State private var renameSmartFilter: SavedFilter?
  @State private var lastSeenFocusRequest: Int = 0
  @FocusState private var searchFieldFocused: Bool
  @Binding var viewMode: NavigatorViewMode

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
      switch viewMode {
      case .tree:
        List {
          if !savedFilters.filters.isEmpty {
            smartFiltersSection
          }
          ForEach(visibleLists, id: \.categoryId) { list in
            listRow(list)
            if isExpanded(list) {
              listContent(list)
            }
          }
        }
        .listStyle(.sidebar)
        .onKeyPress(.space) {
          if searchFieldFocused { return .ignored }
          NotificationCenter.default.post(name: .omToggleQuickLook, object: nil)
          return .handled
        }
      case .table:
        NavigatorTableView(
          model: model,
          selection: selection,
          tagStore: tagStore,
          projectsModel: projectsModel,
          searchText: $searchText)
      }
    }
    .frame(width: viewMode.paneWidth)
    .background(.regularMaterial)
    .onAppear { applyFocusRequestIfNeeded() }
    .onChange(of: focusSearchRequest) { _, _ in applyFocusRequestIfNeeded() }
    .sheet(item: $renameSmartFilter) { filter in
      SmartFilterRenameDialog(initial: filter.name) { newName in
        savedFilters.rename(filter.id, to: newName)
        renameSmartFilter = nil
      } onCancel: { renameSmartFilter = nil }
    }
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
        ForEach(bookmarks, id: \.bookmarkId) { bookmarkRow($0, in: list) }
      }
      if !tracks.isEmpty {
        sectionLabel("Tracks")
        ForEach(tracks, id: \.trackId) { trackRow($0, in: list) }
      }
    } else {
      ForEach(mixed(bookmarks, tracks)) { item in
        switch item {
        case .bookmark(let b): bookmarkRow(b, in: list)
        case .track(let t): trackRow(t, in: list)
        }
      }
    }
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
      .padding(.leading, 18).padding(.top, 4)
  }

  // MARK: - Smart Filters

  @ViewBuilder private var smartFiltersSection: some View {
    HStack(spacing: 6) {
      Button { expandSmartFilters.toggle() } label: {
        Image(systemName: expandSmartFilters ? "chevron.down" : "chevron.right")
          .frame(width: 12)
      }
      .buttonStyle(.borderless)
      Text("Smart Filters").fontWeight(.medium)
      Spacer()
      if savedFilters.activeFilterId != nil {
        Button {
          BookmarksManager.shared().setUserCategoriesVisible(true)
          OMBookmarksHelper.showAllItems()
          NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
          savedFilters.setActive(nil)
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless).help("Clear active filter")
      }
    }
    if expandSmartFilters {
      ForEach(savedFilters.filters) { filter in smartFilterRow(filter) }
    }
  }

  private func smartFilterRow(_ filter: SavedFilter) -> some View {
    let isActive = savedFilters.activeFilterId == filter.id
    return HStack(spacing: 8) {
      Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill"
                                 : "line.3.horizontal.decrease.circle")
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
      Text(filter.name)
      Spacer()
    }
    .padding(.leading, 18)
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .onTapGesture {
      FilterModel.applyOneShot(filter)
      savedFilters.setActive(filter.id)
    }
    .contextMenu {
      Button("Apply") {
        FilterModel.applyOneShot(filter)
        savedFilters.setActive(filter.id)
      }
      Button("Edit in Builder…") { openWindow(id: "filter-builder") }
      Button("Rename…") { renameSmartFilter = filter }
      Divider()
      Button("Delete", role: .destructive) { savedFilters.delete(filter.id) }
    }
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
      Button {
        viewMode = (viewMode == .tree ? .table : .tree)
        viewMode.persist()
      } label: {
        Image(systemName: viewMode == .tree ? "tablecells" : "list.bullet.indent")
      }
      .buttonStyle(.borderless)
      .help(viewMode == .tree ? "Switch to column view" : "Switch to list view")
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
      TextField("Search names, descriptions, tags, regions", text: $searchText)
        .textFieldStyle(.plain)
        .focused($searchFieldFocused)
      if searching {
        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.borderless).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }

  /// When the "Find in Library" command fires, ContentView bumps
  /// `focusSearchRequest`. The change triggers this handler, which defers a
  /// runloop tick so a just-mounted NavigatorView has its `@FocusState` wired
  /// before we set it.
  private func applyFocusRequestIfNeeded() {
    if focusSearchRequest != lastSeenFocusRequest {
      lastSeenFocusRequest = focusSearchRequest
      DispatchQueue.main.async { searchFieldFocused = true }
    }
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
    list.bookmarks.filter { LibrarySearch.matchesBookmark($0, query: searchText) }
  }
  private func matchingTracks(_ list: BookmarkGroup) -> [Track] {
    list.tracks.filter { LibrarySearch.matchesTrack($0, query: searchText) }
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

      Button {
        // Clicking a list header opens the list inspector. Drop any pending
        // multi-selection so the right pane doesn't fight for space.
        selection.clear()
        onSelectList(list)
      } label: {
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


  private func bookmarkRow(_ bm: Bookmark, in list: BookmarkGroup) -> some View {
    let item = NavSelection.bookmark(bm.bookmarkId)
    let isSelected = selection.contains(item)
    let tags = OMBookmarksHelper.tags(forBookmark: bm.bookmarkId)
    return Button { handleClick(item, in: list) } label: {
      HStack(spacing: 8) {
        Circle().fill(Color(nsColor: bm.bookmarkColor)).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 2) {
          Text(bm.bookmarkName)
          if let sub = bookmarkSubtitle(bm) {
            Text(sub).font(.caption).foregroundStyle(.secondary)
          }
          if !tags.isEmpty {
            TagChipRow(tags: tags, limit: 3, onTap: { tag in searchText = tag })
          }
        }
        Spacer()
        let visible = OMBookmarksHelper.isBookmarkVisible(bm.bookmarkId)
        Button { model.setBookmarkVisible(bm.bookmarkId, !visible) } label: {
          Image(systemName: visible ? "eye" : "eye.slash").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
      }
      .padding(.leading, 18)
      .padding(.vertical, 2)
      .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
    }
    .buttonStyle(.plain)
    .onDrag {
      let entity = DraggableEntity(kind: .bookmark, id: UInt64(bm.bookmarkId))
      return NSItemProvider(object: entity.transferString as NSString)
    }
    .contextMenu { rowContextMenu(for: item) }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteBookmark(bm.bookmarkId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  private func trackRow(_ track: Track, in list: BookmarkGroup) -> some View {
    let item = NavSelection.track(track.trackId)
    let isSelected = selection.contains(item)
    let tags = OMBookmarksHelper.tags(forTrack: track.trackId)
    return Button { handleClick(item, in: list) } label: {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 1)
          .fill(Color(nsColor: track.trackColor)).frame(width: 12, height: 3)
        VStack(alignment: .leading, spacing: 2) {
          Text(track.trackName)
          Text(OMBookmarksHelper.formatDistance(meters: Double(track.trackLengthMeters)))
            .font(.caption).foregroundStyle(.secondary)
          if !tags.isEmpty {
            TagChipRow(tags: tags, limit: 3, onTap: { tag in searchText = tag })
          }
        }
        Spacer()
        let visible = OMBookmarksHelper.isTrackVisible(track.trackId)
        Button { model.setTrackVisible(track.trackId, !visible) } label: {
          Image(systemName: visible ? "eye" : "eye.slash").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
      }
      .padding(.leading, 18)
      .padding(.vertical, 2)
      .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
    }
    .buttonStyle(.plain)
    .onDrag {
      let entity = DraggableEntity(kind: .track, id: UInt64(track.trackId))
      return NSItemProvider(object: entity.transferString as NSString)
    }
    .contextMenu { rowContextMenu(for: item) }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteTrack(track.trackId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  // MARK: - Click + context menu

  private func handleClick(_ item: NavSelection, in list: BookmarkGroup) {
    let flags = NSEvent.modifierFlags
    if flags.contains(.command) {
      selection.toggle(item)
    } else if flags.contains(.shift) {
      selection.rangeSelect(to: item, in: orderedSelectables(in: list))
    } else {
      selection.replace(with: item)
      switch item {
      case .bookmark(let id): onSelectBookmark(id)
      case .track(let id): onSelectTrack(id)
      }
    }
  }

  private func orderedSelectables(in list: BookmarkGroup) -> [NavSelection] {
    let bms = bookmarksToShow(list).map { NavSelection.bookmark($0.bookmarkId) }
    let trs = tracksToShow(list).map { NavSelection.track($0.trackId) }
    if groupByType { return bms + trs }
    return mixed(bookmarksToShow(list), tracksToShow(list)).map {
      switch $0 {
      case .bookmark(let b): return .bookmark(b.bookmarkId)
      case .track(let t): return .track(t.trackId)
      }
    }
  }

  /// Right-click on a row opens the same bulk menu single-row or multi-row.
  /// If the row is part of a 2+ selection, the menu's actions target the
  /// whole selection; otherwise it targets just the right-clicked row. A
  /// one-row right-click no longer auto-selects (Finder-style) — the bulk
  /// menu is fed explicit ids and only the Delete path briefly seeds
  /// selection so the shared confirmation dialog has the right target.
  @ViewBuilder private func rowContextMenu(for item: NavSelection) -> some View {
    let (bmIds, trIds): ([MWMMarkID], [MWMTrackID]) = {
      if selection.count >= 2 && selection.contains(item) {
        return (selection.bookmarkIds, selection.trackIds)
      }
      switch item {
      case .bookmark(let id): return ([id], [])
      case .track(let id): return ([], [id])
      }
    }()
    BulkContextMenu(selection: selection, model: model,
                    tagStore: tagStore, projectsModel: projectsModel,
                    bookmarkIds: bmIds, trackIds: trIds)
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

private struct SmartFilterRenameDialog: View {
  let initial: String
  let onSave: (String) -> Void
  let onCancel: () -> Void
  @State private var name: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rename smart filter").font(.headline)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel", action: onCancel)
        Button("Save") { onSave(name) }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 320)
    .onAppear { name = initial }
  }
}
