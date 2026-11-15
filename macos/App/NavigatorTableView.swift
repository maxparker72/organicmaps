import SwiftUI

/// Finder-style flat sortable table of the whole library. Alternative
/// presentation to NavigatorView's tree (toggled in the navigator header).
/// SwiftUI's `Table` gives column sort and multi-select for free; selection
/// is bound through to the same `NavigatorSelectionModel` the tree uses, so
/// the right-pane MultiSelectionInspectorView and all bulk operations work
/// identically regardless of which view mode is active.
struct NavigatorTableView: View {
  @ObservedObject var model: BookmarksNavigatorModel
  @ObservedObject var selection: NavigatorSelectionModel
  @ObservedObject var tagStore: TagStore
  @ObservedObject var projectsModel: ProjectModel
  @Binding var searchText: String

  @State private var sortOrder: [KeyPathComparator<LibraryRow>] = [
    KeyPathComparator(\LibraryRow.name)
  ]

  /// Flattened, filtered, sorted rows. Recomputed on body re-evaluation so it
  /// follows model/sort/search state automatically.
  private var rows: [LibraryRow] {
    var out: [LibraryRow] = []
    for list in model.lists {
      for bm in list.bookmarks where LibrarySearch.matchesBookmark(bm, query: searchText) {
        out.append(LibraryRow(kind: .bookmark(bm), list: list))
      }
      for track in list.tracks where LibrarySearch.matchesTrack(track, query: searchText) {
        out.append(LibraryRow(kind: .track(track), list: list))
      }
    }
    return out.sorted(using: sortOrder)
  }

  // Map the Table's Set<NavSelection> through the selection model so the
  // engine sees changes and downstream views observe them via @ObservedObject.
  private var selectionBinding: Binding<Set<NavSelection>> {
    Binding(get: { selection.selection }, set: { selection.set($0) })
  }

  var body: some View {
    Table(rows, selection: selectionBinding, sortOrder: $sortOrder) {
      TableColumn("") { row in
        Image(systemName: row.isVisible ? "eye" : "eye.slash")
          .foregroundStyle(.secondary)
      }
      .width(20)

      TableColumn("Color", value: \.colorName) { row in
        switch row.kind {
        case .bookmark(let bm):
          Circle().fill(Color(nsColor: bm.bookmarkColor)).frame(width: 10, height: 10)
        case .track(let t):
          RoundedRectangle(cornerRadius: 1)
            .fill(Color(nsColor: t.trackColor)).frame(width: 14, height: 3)
        }
      }
      .width(40)

      TableColumn("Name", value: \.name)

      TableColumn("Kind", value: \.kindLabel) { row in
        Text(row.kindLabel).foregroundStyle(.secondary)
      }
      .width(70)

      TableColumn("List", value: \.listTitle)

      TableColumn("Length", value: \.lengthMeters) { row in
        Text(row.lengthMeters > 0
             ? OMBookmarksHelper.formatDistance(meters: row.lengthMeters) : "—")
      }
      .width(90)

      TableColumn("Distance", value: \.distanceMeters) { row in
        Text(row.distanceMeters > 0
             ? OMBookmarksHelper.formatDistance(meters: row.distanceMeters) : "—")
      }
      .width(90)

      TableColumn("Tags", value: \.tagsJoined) { row in
        TagChipRow(tags: row.tagArray, limit: 4, onTap: { tag in searchText = tag })
      }

      TableColumn("Region", value: \.regionName) { row in
        Text(row.regionName).foregroundStyle(.secondary)
      }
    }
    .contextMenu(forSelectionType: NavSelection.self) { items in
      // Same bulk menu for single-row and multi-row right-clicks — a single
      // item is a one-item batch. Items come from the Table's own
      // right-click hit, so we can feed them straight in.
      if !items.isEmpty {
        let bmIds = items.compactMap { if case let .bookmark(id) = $0 { return id } else { return nil } }
        let trIds = items.compactMap { if case let .track(id) = $0 { return id } else { return nil } }
        BulkContextMenu(selection: selection, model: model,
                        tagStore: tagStore, projectsModel: projectsModel,
                        bookmarkIds: bmIds, trackIds: trIds)
      }
    } primaryAction: { items in
      // Double-click / Return: open the engine place-page for a single
      // primary-actioned row. Matches Finder's "open" semantics.
      if items.count == 1, let only = items.first {
        engineFocus(only)
      }
    }
    .onChange(of: selection.count) { _, count in
      // Single-row selection drives engine place-page (matches the tree view's
      // single-click behaviour). 2+ items leave engine selection alone — the
      // multi-selection inspector takes over the right pane via ContentView.
      if count == 1, let only = selection.selection.first {
        engineFocus(only)
      }
    }
    .onKeyPress(.space) {
      NotificationCenter.default.post(name: .omToggleQuickLook, object: nil)
      return .handled
    }
  }

  private func engineFocus(_ item: NavSelection) {
    switch item {
    case .bookmark(let id): model.showBookmarkOnMap(id)
    case .track(let id): model.showTrackOnMap(id)
    }
  }
}

// MARK: - Row model

/// One row in the flat library table: either a Bookmark or a Track, plus the
/// parent list (needed for the List column). Identifiable by `NavSelection`
/// so the Table's selection set is directly bindable to
/// `NavigatorSelectionModel.selection`.
struct LibraryRow: Identifiable {
  enum Kind {
    case bookmark(Bookmark)
    case track(Track)
  }

  let kind: Kind
  let list: BookmarkGroup

  var id: NavSelection {
    switch kind {
    case .bookmark(let b): return .bookmark(b.bookmarkId)
    case .track(let t): return .track(t.trackId)
    }
  }

  var isBookmark: Bool { if case .bookmark = kind { return true } else { return false } }
  var kindLabel: String { isBookmark ? "Bookmark" : "Track" }

  var name: String {
    switch kind {
    case .bookmark(let b): return b.bookmarkName
    case .track(let t): return t.trackName
    }
  }

  var listTitle: String { list.title }

  var colorName: String {
    switch kind {
    case .bookmark(let b): return BookmarkColor.closest(to: b.bookmarkColor).displayName
    case .track(let t): return BookmarkColor.closest(to: t.trackColor).displayName
    }
  }

  var lengthMeters: Double {
    switch kind {
    case .bookmark: return 0
    case .track(let t): return Double(t.trackLengthMeters)
    }
  }

  // For bookmarks: distance from the user's current position (negative when
  // unknown, normalized to 0 here so the sort and the "—" rendering align).
  var distanceMeters: Double {
    switch kind {
    case .bookmark(let b):
      let m = OMBookmarksHelper.metersFromCurrentPosition(
        toLat: b.locationCoordinate.latitude, lon: b.locationCoordinate.longitude)
      return m < 0 ? 0 : m
    case .track: return 0
    }
  }

  var tagArray: [String] {
    switch kind {
    case .bookmark(let b): return OMBookmarksHelper.tags(forBookmark: b.bookmarkId)
    case .track(let t): return OMBookmarksHelper.tags(forTrack: t.trackId)
    }
  }

  var tagsJoined: String { tagArray.joined(separator: ", ") }

  var regionName: String {
    let chain: [String]
    switch kind {
    case .bookmark(let b): chain = OMBookmarksHelper.regions(forBookmark: b.bookmarkId)
    case .track(let t): chain = OMBookmarksHelper.regions(forTrack: t.trackId)
    }
    guard let leaf = chain.first else { return "" }
    return OMBookmarksHelper.displayName(forRegion: leaf)
  }

  var isVisible: Bool {
    switch kind {
    case .bookmark(let b): return OMBookmarksHelper.isBookmarkVisible(b.bookmarkId)
    case .track(let t): return OMBookmarksHelper.isTrackVisible(t.trackId)
    }
  }
}
