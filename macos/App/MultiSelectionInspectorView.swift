import SwiftUI

/// Right-hand pane content when the navigator has 2+ items selected. Mirrors
/// PlacePageView's visual structure (340pt wide, regularMaterial, header +
/// scroll content) so the swap doesn't feel jarring.
struct MultiSelectionInspectorView: View {
  @ObservedObject var selection: NavigatorSelectionModel
  @ObservedObject var navigatorModel: BookmarksNavigatorModel
  @ObservedObject var tagStore: TagStore
  @ObservedObject var projectsModel: ProjectModel
  let onHide: () -> Void

  @State private var newTagSheet = false
  @State private var newTagText = ""
  @State private var showColorPicker = false

  private var bookmarkCount: Int { selection.bookmarkIds.count }
  private var trackCount: Int { selection.trackIds.count }

  // Lazy: recomputed when the selection changes (Set hash). Tracks only —
  // bookmarks have no per-item stats to aggregate beyond a count.
  private var trackStats: [OMTrackStats] {
    selection.trackIds.compactMap { OMBookmarksHelper.trackStats(forTrack: $0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          summary
          if !trackStats.isEmpty {
            section("Track statistics") {
              TrackStatsView(mode: .aggregate(trackStats))
            }
          }
          if !colorBreakdown.isEmpty {
            section("Colors") { ChipFlow(items: colorBreakdown) }
          }
          if !listBreakdown.isEmpty {
            section("Lists") { ChipFlow(items: listBreakdown) }
          }
          section("Actions") { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
    }
    .frame(width: 340)
    .background(.regularMaterial)
    .sheet(isPresented: $newTagSheet) {
      newTagDialog
    }
  }

  // MARK: - Header & summary

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(selection.count) selected").font(.headline)
        Text(itemBreakdownText).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: onHide) { Image(systemName: "sidebar.right") }
        .buttonStyle(.borderless).help("Hide info pane")
      Button { selection.clear() } label: { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(.borderless).help("Clear selection")
    }
    .padding(16)
  }

  private var itemBreakdownText: String {
    switch (bookmarkCount, trackCount) {
    case (let b, 0): return "\(b) \(b == 1 ? "bookmark" : "bookmarks")"
    case (0, let t): return "\(t) \(t == 1 ? "track" : "tracks")"
    case (let b, let t): return "\(b) \(b == 1 ? "bookmark" : "bookmarks") · \(t) \(t == 1 ? "track" : "tracks")"
    }
  }

  @ViewBuilder private var summary: some View {
    let visibleBmCount = selection.bookmarkIds.reduce(0) {
      $0 + (OMBookmarksHelper.isBookmarkVisible($1) ? 1 : 0)
    }
    let visibleTrCount = selection.trackIds.reduce(0) {
      $0 + (OMBookmarksHelper.isTrackVisible($1) ? 1 : 0)
    }
    let visibleTotal = visibleBmCount + visibleTrCount
    HStack(spacing: 8) {
      Image(systemName: visibleTotal == selection.count
            ? "eye" : (visibleTotal == 0 ? "eye.slash" : "eye.trianglebadge.exclamationmark"))
        .foregroundStyle(.secondary)
      Text(visibleTotal == selection.count ? "All visible"
           : (visibleTotal == 0 ? "All hidden" : "\(visibleTotal) of \(selection.count) visible"))
        .font(.subheadline).foregroundStyle(.secondary)
    }
  }

  // MARK: - Breakdown chips

  private var colorBreakdown: [String] {
    var counts: [String: Int] = [:]
    for bm in matchedBookmarks() {
      counts[BookmarkColor.closest(to: bm.bookmarkColor).displayName, default: 0] += 1
    }
    // Tracks store an arbitrary dp::Color; snap to the nearest palette entry
    // so the breakdown groups by visual colour rather than by exact RGBA.
    for track in matchedTracks() {
      let snapped = BookmarkColor.closest(to: track.trackColor)
      counts[snapped.displayName, default: 0] += 1
    }
    return counts.sorted { $0.value > $1.value }.map { "\($0.key) · \($0.value)" }
  }

  private var listBreakdown: [String] {
    var counts: [String: Int] = [:]
    for list in navigatorModel.lists {
      let inList = list.bookmarks.filter { selection.contains(.bookmark($0.bookmarkId)) }.count
        + list.tracks.filter { selection.contains(.track($0.trackId)) }.count
      if inList > 0 { counts[list.title] = inList }
    }
    return counts.sorted { $0.value > $1.value }.map { "\($0.key) · \($0.value)" }
  }

  private func matchedBookmarks() -> [Bookmark] {
    var result: [Bookmark] = []
    for list in navigatorModel.lists {
      for bm in list.bookmarks where selection.contains(.bookmark(bm.bookmarkId)) {
        result.append(bm)
      }
    }
    return result
  }

  private func matchedTracks() -> [Track] {
    var result: [Track] = []
    for list in navigatorModel.lists {
      for track in list.tracks where selection.contains(.track(track.trackId)) {
        result.append(track)
      }
    }
    return result
  }

  // MARK: - Actions

  private var actions: some View {
    VStack(alignment: .leading, spacing: 10) {
      moveMenu
      colorMenu
      tagAddMenu
      tagRemoveMenu
      projectMenu
      HStack(spacing: 10) {
        Button { setVisible(true) } label: {
          Label("Show", systemImage: "eye")
        }
        Button { setVisible(false) } label: {
          Label("Hide", systemImage: "eye.slash")
        }
      }
      Button(role: .destructive) {
        // Same shared confirmation as the context-menu Delete path.
        selection.pendingBulkDelete = true
      } label: {
        Label("Delete \(selection.count) items…", systemImage: "trash")
      }
      .controlSize(.regular)
    }
  }

  private var moveMenu: some View {
    Menu {
      ForEach(navigatorModel.lists, id: \.categoryId) { list in
        Button(list.title) {
          navigatorModel.moveItems(
            bookmarkIds: selection.bookmarkNSNumbers,
            trackIds: selection.trackNSNumbers,
            to: list.categoryId)
        }
      }
    } label: { Label("Move to list…", systemImage: "folder") }
  }

  private var colorMenu: some View {
    Button {
      showColorPicker.toggle()
    } label: { Label("Set color…", systemImage: "paintpalette") }
    .popover(isPresented: $showColorPicker, arrowEdge: .leading) {
      colorSwatchGrid
    }
  }

  /// Popover content for Set Color. Native macOS menus template-tint their
  /// item images to the system text colour and ignore SwiftUI's
  /// foregroundStyle on a Label icon, so colored swatches in a Menu render
  /// black; a popover sidesteps the bridge entirely and lets us draw real
  /// SwiftUI Circles. Mirrors the swatch grid in EntityEditView.
  private var colorSwatchGrid: some View {
    let columns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8)
    return LazyVGrid(columns: columns, spacing: 6) {
      ForEach(BookmarkColor.palette, id: \.self) { color in
        Circle()
          .fill(color.swiftUIColor)
          .frame(width: 22, height: 22)
          .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
          .onTapGesture {
            navigatorModel.setColorForItems(
              bookmarkIds: selection.bookmarkNSNumbers,
              trackIds: selection.trackNSNumbers,
              color: color)
            showColorPicker = false
          }
          .help(color.displayName)
      }
    }
    .padding(10)
  }

  private var tagAddMenu: some View {
    Menu {
      if tagStore.allTags.isEmpty {
        Text("No tags yet").foregroundStyle(.secondary)
      } else {
        ForEach(tagStore.allTags, id: \.self) { tag in
          Button(tag) { addTag(tag) }
        }
      }
      Divider()
      Button("New tag…") { newTagText = ""; newTagSheet = true }
    } label: { Label("Add tag…", systemImage: "tag") }
  }

  private var tagRemoveMenu: some View {
    Menu {
      let presentTags = currentTagsAcrossSelection()
      if presentTags.isEmpty {
        Text("No tags on selection").foregroundStyle(.secondary)
      } else {
        ForEach(presentTags, id: \.self) { tag in
          Button(tag) { removeTag(tag) }
        }
      }
    } label: { Label("Remove tag…", systemImage: "tag.slash") }
  }

  private var projectMenu: some View {
    Menu {
      if projectsModel.projects.isEmpty {
        Text("No projects yet").foregroundStyle(.secondary)
      } else {
        ForEach(projectsModel.projects) { project in
          Button(project.name) { addToProject(project) }
        }
      }
    } label: { Label("Add to project…", systemImage: "rectangle.stack.badge.plus") }
  }

  private var newTagDialog: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New tag").font(.headline)
      TextField("Tag name", text: $newTagText)
        .textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel") { newTagSheet = false; newTagText = "" }
        Button("Add") {
          addTag(newTagText)
          newTagSheet = false; newTagText = ""
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 320)
  }

  // MARK: - Action implementations

  private func setVisible(_ visible: Bool) {
    navigatorModel.setItemsVisible(
      bookmarkIds: selection.bookmarkNSNumbers,
      trackIds: selection.trackNSNumbers,
      visible: visible)
  }

  private func addTag(_ tag: String) {
    navigatorModel.addTag(tag, bookmarkIds: selection.bookmarkIds, trackIds: selection.trackIds)
  }

  private func removeTag(_ tag: String) {
    navigatorModel.removeTag(tag, bookmarkIds: selection.bookmarkIds, trackIds: selection.trackIds)
  }

  private func addToProject(_ project: Project) {
    for id in selection.bookmarkIds {
      projectsModel.addBookmark(id, to: project)
    }
    for id in selection.trackIds {
      projectsModel.addTrack(id, to: project)
    }
  }

  private func currentTagsAcrossSelection() -> [String] {
    var seen = Set<String>()
    for id in selection.bookmarkIds {
      for tag in OMBookmarksHelper.tags(forBookmark: id) { seen.insert(tag) }
    }
    for id in selection.trackIds {
      for tag in OMBookmarksHelper.tags(forTrack: id) { seen.insert(tag) }
    }
    return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  // MARK: - Layout helpers

  private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      content()
    }
  }
}

/// Wraps a flat list of short text chips and wraps onto the next line when
/// horizontal space runs out. SwiftUI's `Layout` would be more elegant but
/// `LazyVGrid` covers the common case with no custom layout code.
private struct ChipFlow: View {
  let items: [String]

  var body: some View {
    let columns = [GridItem(.adaptive(minimum: 90, maximum: 200), spacing: 6, alignment: .leading)]
    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
      ForEach(items, id: \.self) { item in
        Text(item)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.secondary.opacity(0.15), in: Capsule())
          .lineLimit(1)
      }
    }
  }
}

