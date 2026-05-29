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

  @ObservedObject private var savedFilters = SavedFiltersStore.shared
  @Environment(\.openWindow) private var openWindow
  @State private var expandSmartFilters: Bool = true
  @State private var renameSmartFilter: SavedFilter?

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
    }
    .frame(width: 300)
    .background(.regularMaterial)
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

  @ViewBuilder private func moveMenu(_ action: @escaping (MWMMarkGroupID) -> Void) -> some View {
    Menu("Move to") {
      ForEach(model.lists, id: \.categoryId) { list in
        Button(list.title) { action(list.categoryId) }
      }
    }
  }

  private func bookmarkRow(_ bm: Bookmark, in list: BookmarkGroup) -> some View {
    let item = NavSelection.bookmark(bm.bookmarkId)
    let isSelected = selection.contains(item)
    return Button { handleClick(item, in: list) } label: {
      HStack(spacing: 8) {
        Circle().fill(bm.bookmarkColor.swiftUIColor).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 1) {
          Text(bm.bookmarkName)
          if let sub = bookmarkSubtitle(bm) {
            Text(sub).font(.caption).foregroundStyle(.secondary)
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
    .contextMenu { contextMenu(for: item, singleDelete: { model.deleteBookmark(bm.bookmarkId) },
                                 singleMove: { model.moveBookmark(bm.bookmarkId, to: $0) }) }
    .swipeActions(edge: .trailing) {
      Button(role: .destructive) { model.deleteBookmark(bm.bookmarkId) } label: { Label("Delete", systemImage: "trash") }
    }
  }

  private func trackRow(_ track: Track, in list: BookmarkGroup) -> some View {
    let item = NavSelection.track(track.trackId)
    let isSelected = selection.contains(item)
    return Button { handleClick(item, in: list) } label: {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 1)
          .fill(Color(nsColor: track.trackColor)).frame(width: 12, height: 3)
        VStack(alignment: .leading, spacing: 1) {
          Text(track.trackName)
          Text(OMBookmarksHelper.formatDistance(meters: Double(track.trackLengthMeters)))
            .font(.caption).foregroundStyle(.secondary)
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
    .contextMenu { contextMenu(for: item, singleDelete: { model.deleteTrack(track.trackId) },
                                 singleMove: { model.moveTrack(track.trackId, to: $0) }) }
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

  /// Right-click on a row opens this menu. If the right-clicked row is part
  /// of a 2+ selection, expose bulk operations on the whole set; otherwise
  /// just the single-item move/delete (the row is not auto-added — match
  /// Finder, which leaves selection alone when right-clicking outside it).
  @ViewBuilder private func contextMenu(for item: NavSelection,
                                        singleDelete: @escaping () -> Void,
                                        singleMove: @escaping (MWMMarkGroupID) -> Void) -> some View {
    if selection.contains(item) && selection.count >= 2 {
      bulkContextMenu
    } else {
      moveMenu(singleMove)
      Button("Delete", role: .destructive, action: singleDelete)
    }
  }

  @ViewBuilder private var bulkContextMenu: some View {
    Menu("Move to") {
      ForEach(model.lists, id: \.categoryId) { list in
        Button(list.title) {
          model.moveItems(bookmarkIds: selection.bookmarkNSNumbers,
                          trackIds: selection.trackNSNumbers,
                          to: list.categoryId)
        }
      }
    }
    Menu("Set color") {
      ForEach(BookmarkColor.palette, id: \.self) { color in
        Button(color.displayName) {
          model.setColorForItems(bookmarkIds: selection.bookmarkNSNumbers,
                                 trackIds: selection.trackNSNumbers,
                                 color: color)
        }
      }
    }
    Menu("Add tag") {
      if tagStore.allTags.isEmpty {
        Text("No tags yet").foregroundStyle(.secondary)
      } else {
        ForEach(tagStore.allTags, id: \.self) { tag in
          Button(tag) {
            model.addTag(tag, bookmarkIds: selection.bookmarkIds, trackIds: selection.trackIds)
          }
        }
      }
    }
    Menu("Add to project") {
      if projectsModel.projects.isEmpty {
        Text("No projects yet").foregroundStyle(.secondary)
      } else {
        ForEach(projectsModel.projects) { project in
          Button(project.name) {
            for id in selection.bookmarkIds { projectsModel.addBookmark(id, to: project) }
            for id in selection.trackIds { projectsModel.addTrack(id, to: project) }
          }
        }
      }
    }
    Divider()
    Button("Show") {
      model.setItemsVisible(bookmarkIds: selection.bookmarkNSNumbers,
                            trackIds: selection.trackNSNumbers, visible: true)
    }
    Button("Hide") {
      model.setItemsVisible(bookmarkIds: selection.bookmarkNSNumbers,
                            trackIds: selection.trackNSNumbers, visible: false)
    }
    Divider()
    Button("Delete \(selection.count) items", role: .destructive) {
      let bIds = selection.bookmarkNSNumbers
      let tIds = selection.trackNSNumbers
      selection.clear()
      model.deleteItems(bookmarkIds: bIds, trackIds: tIds)
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
