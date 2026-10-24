import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Environment(\.undoManager) private var envUndoManager

  @State private var showNavigator = false
  @State private var showProjects = false
  @State private var paneHidden = false
  @State private var selectedList: BookmarkGroup?
  @State private var showSearch = false

  @StateObject private var downloadModel = MapDownloadModel()
  @StateObject private var layersModel = LayersModel()
  @StateObject private var placePageModel = PlacePageModel()
  @StateObject private var bookmarksModel = BookmarksNavigatorModel()
  @StateObject private var projectsModel = ProjectModel()
  @StateObject private var routingModel = RoutingModel()
  @StateObject private var searchModel = SearchModel()
  @StateObject private var importNormalizer = ImportNormalizer()
  @StateObject private var navSelection = NavigatorSelectionModel()
  @StateObject private var tagStore = TagStore()
  @ObservedObject private var importCoordinator = ImportCoordinator.shared

  @State private var buildings3D: Bool = OMPreferences.buildings3D()
  @State private var focusLibrarySearchRequest: Int = 0
  @State private var navigatorViewMode: NavigatorViewMode = NavigatorViewMode.loadPersisted()
  @State private var quickLookItem: NavSelection?

  private var hasInfo: Bool {
    selectedList != nil || placePageModel.info != nil || navSelection.count >= 2
  }

  var body: some View {
    NavigationStack {
      MapView()
        .ignoresSafeArea()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
          // Gather every dropped URL first, then hand the whole batch to
          // ImportCoordinator. The coordinator skips its sheet for a
          // single-file drop, so casual single-file behaviour is preserved.
          // loadObject completes on background queues, so each result is stored
          // on the main queue in its own slot, which also keeps the drop order.
          var urls = [URL?](repeating: nil, count: providers.count)
          let group = DispatchGroup()
          for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
              DispatchQueue.main.async {
                urls[index] = url
                group.leave()
              }
            }
          }
          group.notify(queue: .main) {
            ImportCoordinator.shared.begin(urls.compactMap { $0 })
          }
          return true
        }
        .overlay(alignment: .bottom) {
          DownloadBanner(model: downloadModel).padding(.bottom, 16)
        }
        .overlay(alignment: .leading) { leadingOverlay }
        .overlay(alignment: .trailing) { infoOverlay }
        .overlay(alignment: .top) {
          if routingModel.hasPoints {
            RoutePlannerView(model: routingModel, onSaved: { _ in bookmarksModel.refresh() })
              .padding(.top, 16)
              .transition(.move(edge: .top))
          }
        }
        .overlay(alignment: .topLeading) {
          if showSearch {
            SearchView(
              model: searchModel,
              onDismiss: { searchModel.clearMap(); showSearch = false },
              // Pick-a-result keeps the dialog open so pins and the picked
              // place's info pane are visible together; the user dismisses
              // explicitly via ✕ / Esc / the toolbar toggle.
              onResultSelected: {})
              // Shift right when the bookmarks navigator and/or projects pane
              // (300pt each) are open so the panels don't overlap.
              .padding(.leading, leadingPanesWidth + 16)
              .padding(.top, 16)
              .transition(.move(edge: .leading).combined(with: .opacity))
          }
        }
        .animation(.easeInOut(duration: 0.2), value: showNavigator)
        .animation(.easeInOut(duration: 0.2), value: showProjects)
        .animation(.easeInOut(duration: 0.2), value: navigatorViewMode)
        .animation(.easeInOut(duration: 0.2), value: paneHidden)
        .animation(.easeInOut(duration: 0.2), value: selectedList?.categoryId)
        .animation(.easeInOut(duration: 0.2), value: placePageModel.info == nil)
        .animation(.easeInOut(duration: 0.2), value: showSearch)
        .onChange(of: placePageModel.openToken) { _, _ in
          selectedList = nil
          // paneHidden is sticky on purpose — once the user closes the info
          // pane (Cmd-I or the toolbar info button), subsequent map clicks
          // shouldn't reopen it. Quick Look (Space / Cmd-Y) is the inline
          // alternative for casual previews.
          // Tapping a different feature deactivates the previous selection,
          // which the engine uses as a trigger to wipe SEARCH user-marks.
          // Repaint pins after the new selection settles.
          searchModel.refillPinsIfLive()
        }
        .onChange(of: placePageModel.info == nil) { _, isNil in
          // Tapping empty space deactivates without re-activating; same wipe,
          // same repaint.
          if isNil { searchModel.refillPinsIfLive() }
        }
        .onChange(of: bookmarksModel.lists.map(\.categoryId)) { _, ids in
          if let sel = selectedList, !ids.contains(sel.categoryId) {
            selectedList = nil
          }
        }
        .onChange(of: navSelection.count) { _, count in
          // Once the navigator selection has 2+ items the right pane swaps to
          // the multi-selection inspector; tell the engine to forget its own
          // place-page selection so the two don't fight for the same slot.
          if count >= 2 {
            paneHidden = false
            FrameworkHelper.deactivateMapSelection()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .omFindInLibrary)) { _ in
          // Show the navigator (if hidden) and bump the focus counter so the
          // navigator's search field gains keyboard focus on the next runloop.
          showNavigator = true
          focusLibrarySearchRequest += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .omToggleQuickLook)) { _ in
          // Toggle: an open Quick Look closes; otherwise resolve a target.
          // Engine selection (a map-pin click, an in-app search result) wins
          // over the navigator's last selection — Cmd-Y on a freshly-clicked
          // pin used to surface stale navigator state instead of the pin the
          // user just touched.
          if quickLookItem != nil {
            quickLookItem = nil
            return
          }
          if let info = placePageModel.info, info.isBookmark {
            quickLookItem = .bookmark(info.bookmarkId)
          } else if let info = placePageModel.info, info.isTrack {
            quickLookItem = .track(info.trackId)
          } else if navSelection.count == 1, let only = navSelection.selection.first {
            quickLookItem = only
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .omSelectMatchingFilter)) { note in
          // "Select Matching" from the Filter window — pop the navigator open
          // and load the filter's matched ids into navSelection so the user
          // can run bulk Move / Set Color / Add Tag against the result.
          guard let bms = note.userInfo?["bookmarks"] as? [UInt64],
                let trs = note.userInfo?["tracks"] as? [UInt64] else { return }
          var items: Set<NavSelection> = []
          for id in bms { items.insert(.bookmark(MWMMarkID(id))) }
          for id in trs { items.insert(.track(MWMTrackID(id))) }
          navSelection.set(items)
          showNavigator = true
        }
        .onAppear {
          downloadModel.start()
          placePageModel.start()
          bookmarksModel.refresh()
          bookmarksModel.undoManager = envUndoManager
        }
        .toolbar { toolbarContent }
        .sheet(item: $importCoordinator.pendingSheet) { state in
          ImportDestinationSheet(
            fileCount: state.fileCount,
            ignoredCount: state.ignoredCount,
            bookmarksModel: bookmarksModel,
            projectsModel: projectsModel,
            tagStore: tagStore,
            onConfirm: { importCoordinator.confirm($0) },
            onCancel: { importCoordinator.cancelSheet() })
        }
        .sheet(item: $quickLookItem) { item in
          QuickLookView(item: item, onClose: { quickLookItem = nil })
        }
        .confirmationDialog(
          "Delete \(navSelection.count) items?",
          isPresented: $navSelection.pendingBulkDelete,
          titleVisibility: .visible
        ) {
          Button("Delete", role: .destructive) {
            let b = navSelection.bookmarkNSNumbers
            let t = navSelection.trackNSNumbers
            navSelection.clear()
            bookmarksModel.deleteItems(bookmarkIds: b, trackIds: t)
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Cmd-Z can undo moves, tags, colors and visibility — but not deletions.")
        }
    }
  }

  // MARK: - Overlays

  private var leadingPanesWidth: CGFloat {
    (showNavigator ? navigatorViewMode.paneWidth : 0) + (showProjects ? 300 : 0)
  }

  // Side-by-side leading panes: bookmarks navigator and projects pane. Each is
  // independently toggleable; the primary projects workflow is dragging items
  // from the navigator into a project, so both must be able to be visible at once.
  @ViewBuilder private var leadingOverlay: some View {
    HStack(spacing: 0) {
      if showNavigator {
        NavigatorView(
          model: bookmarksModel,
          selection: navSelection,
          tagStore: tagStore,
          projectsModel: projectsModel,
          onSelectList: { list in
            selectedList = list
            paneHidden = false
          },
          onSelectBookmark: { bookmarksModel.showBookmarkOnMap($0) },
          onSelectTrack: { bookmarksModel.showTrackOnMap($0) },
          onHide: {
            // Drop the multi-selection when the pane is hidden — otherwise
            // Cmd-Y / "Find in Library" / Show-Hide commands resurface stale
            // state long after the user has visibly cleared the workspace.
            showNavigator = false
            navSelection.clear()
          },
          focusSearchRequest: focusLibrarySearchRequest,
          viewMode: $navigatorViewMode)
          .transition(.move(edge: .leading))
      }
      if showProjects {
        ProjectsPaneView(
          projects: projectsModel,
          bookmarks: bookmarksModel,
          onHide: { showProjects = false })
          .transition(.move(edge: .leading))
      }
    }
  }

  @ViewBuilder private var infoOverlay: some View {
    if !paneHidden {
      // Order matters: a 2+ multi-selection wins, then list inspector, then
      // engine place-page. Single-item navigator selection routes through the
      // engine so it falls naturally into the place-page branch.
      if navSelection.count >= 2 {
        MultiSelectionInspectorView(
          selection: navSelection,
          navigatorModel: bookmarksModel,
          tagStore: tagStore,
          projectsModel: projectsModel,
          onHide: { paneHidden = true })
          .transition(.move(edge: .trailing))
      } else if let list = selectedList, bookmarksModel.lists.contains(where: { $0.categoryId == list.categoryId }) {
        ListInfoView(
          list: list,
          onClear: { selectedList = nil },
          onHide: { paneHidden = true },
          onChanged: {
            let id = list.categoryId
            bookmarksModel.refresh()
            selectedList = bookmarksModel.lists.first { $0.categoryId == id }
          },
          onDeleted: { selectedList = nil; bookmarksModel.refresh() })
          .transition(.move(edge: .trailing))
      } else if let info = placePageModel.info {
        PlacePageView(
          info: info,
          onClear: { placePageModel.clearSelection() },
          onHide: { paneHidden = true },
          onAddBookmark: {
            OMBookmarksHelper.addBookmarkForCurrentPlace()
            bookmarksModel.refresh()
          },
          onChanged: { bookmarksModel.refresh() },
          onDeleted: {
            placePageModel.clearSelection()
            bookmarksModel.refresh()
          },
          onSetStart: { OMRoutingHelper.setStartForCurrentPlace() },
          onPrepend: { OMRoutingHelper.prependForCurrentPlace() },
          onAddStopAtEnd: { OMRoutingHelper.addStopBeforeFinishForCurrentPlace() },
          onAddStopAtFront: { OMRoutingHelper.addStopAfterStartForCurrentPlace() },
          onSetFinish: { OMRoutingHelper.setFinishForCurrentPlace() },
          onAppend: { OMRoutingHelper.appendForCurrentPlace() })
          .transition(.move(edge: .trailing))
      }
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      // Folder reads as "library / collection" — the navigator is the
      // bookmark organisation surface. Projects move to rectangle.stack
      // (collections of items) so the two are visually distinct.
      Button { showNavigator.toggle() } label: { Image(systemName: "folder") }
        .help("Bookmarks")
      Button { showProjects.toggle() } label: { Image(systemName: "rectangle.stack") }
        .help("Projects")
        .keyboardShortcut("p", modifiers: [.command, .shift])
      Button {
        if showSearch { searchModel.clearMap() }
        showSearch.toggle()
      } label: { Image(systemName: "magnifyingglass") }
        .help("Search")
        .keyboardShortcut("f", modifiers: .command)
    }
    ToolbarItemGroup(placement: .automatic) {
      Menu {
        Section("Layers") {
          Toggle("Subway", isOn: Binding(get: { layersModel.subway }, set: layersModel.setSubway))
          Toggle("Isolines", isOn: Binding(get: { layersModel.isolines }, set: layersModel.setIsolines))
          Toggle("Outdoor", isOn: Binding(get: { layersModel.outdoor }, set: layersModel.setOutdoor))
          Toggle("Hiking", isOn: Binding(get: { layersModel.hiking }, set: layersModel.setHiking))
          Toggle("Cycling", isOn: Binding(get: { layersModel.cycling }, set: layersModel.setCycling))
        }
        Section("3D") {
          Toggle("3D buildings", isOn: Binding(
            get: { buildings3D },
            set: { v in buildings3D = v; OMPreferences.setBuildings3D(v) }))
        }
      } label: {
        Image(systemName: "square.3.layers.3d")
      }
      .help("Map layers")

      Button { OMLocationController.followMyPosition() } label: { Image(systemName: "location") }
        .help("Show my location")
      Button { OMMapControls.rotateToNorth() } label: { Image(systemName: "location.north.line") }
        .help("Orient north")
      Button { paneHidden.toggle() } label: { Image(systemName: "info.circle") }
        .help(paneHidden ? "Show info pane" : "Hide info pane")
        .keyboardShortcut("i", modifiers: .command)
        .disabled(!hasInfo)
    }
  }
}

/// A subtle "Press ⇧⏎ to download <region>" watermark that morphs into a
/// linear progress card while the download runs, then disappears.
private struct DownloadBanner: View {
  @ObservedObject var model: MapDownloadModel

  var body: some View {
    switch model.status {
    case .notDownloaded, .onDiskOutOfDate:
      Button(action: model.download) { promptCard }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .shift)
    case .downloading, .inQueue:
      progressCard
    case .error:
      Button(action: model.retry) { retryCard }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .shift)
    case .none, .onDisk:
      EmptyView()
    @unknown default:
      EmptyView()
    }
  }

  private var promptCard: some View {
    watermarkCard {
      VStack(spacing: 4) {
        Text("Press ⇧⏎ to \(verb) \(model.name)").font(.headline)
        Text(sizeString).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var progressCard: some View {
    watermarkCard {
      VStack(spacing: 10) {
        Text(model.status == .inQueue ? "\(model.name) queued" : "Downloading \(model.name)")
          .font(.headline)
        ProgressView(value: model.progressFraction)
          .progressViewStyle(.linear)
          .frame(width: 260)
        Text("\(Int(model.progressFraction * 100))%")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var retryCard: some View {
    watermarkCard {
      VStack(spacing: 4) {
        Text("Couldn't download \(model.name)").font(.headline)
        Text("Press ⇧⏎ to retry").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var verb: String { model.status == .onDiskOutOfDate ? "update" : "download" }
  private var sizeString: String {
    ByteCountFormatter.string(fromByteCount: Int64(model.sizeBytes), countStyle: .file)
  }

  @ViewBuilder
  private func watermarkCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.horizontal, 22)
      .padding(.vertical, 16)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .shadow(radius: 10)
  }
}
