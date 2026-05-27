import SwiftUI

/// Left slide-over pane: a flat list of bookmark lists, each expandable to its
/// bookmarks and tracks. Selecting an item drives the right-hand info pane.
struct NavigatorView: View {
  @ObservedObject var model: BookmarksNavigatorModel
  let onSelectList: (BookmarkGroup) -> Void
  let onSelectBookmark: (MWMMarkID) -> Void
  let onSelectTrack: (MWMTrackID) -> Void
  let onHide: () -> Void

  @State private var expanded: Set<MWMMarkGroupID> = []
  @State private var showNewList = false
  @State private var newListName = ""

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      List {
        ForEach(model.lists, id: \.categoryId) { list in
          listRow(list)
          if expanded.contains(list.categoryId) {
            ForEach(list.bookmarks, id: \.bookmarkId) { bookmarkRow($0) }
            ForEach(list.tracks, id: \.trackId) { trackRow($0) }
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

  private var header: some View {
    HStack(spacing: 8) {
      Text("Bookmarks").font(.headline)
      Spacer()
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
