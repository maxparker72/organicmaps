import SwiftUI

struct ContentView: View {
  @State private var showNavigator = false
  @State private var paneHidden = false
  @State private var selectedList: BookmarkGroup?

  @StateObject private var downloadModel = MapDownloadModel()
  @StateObject private var layersModel = LayersModel()
  @StateObject private var placePageModel = PlacePageModel()
  @StateObject private var bookmarksModel = BookmarksNavigatorModel()

  private var hasInfo: Bool { selectedList != nil || placePageModel.info != nil }

  var body: some View {
    NavigationStack {
      MapView()
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
          DownloadBanner(model: downloadModel).padding(.bottom, 16)
        }
        .overlay(alignment: .leading) { navigatorOverlay }
        .overlay(alignment: .trailing) { infoOverlay }
        .animation(.easeInOut(duration: 0.2), value: showNavigator)
        .animation(.easeInOut(duration: 0.2), value: paneHidden)
        .animation(.easeInOut(duration: 0.2), value: selectedList?.categoryId)
        .animation(.easeInOut(duration: 0.2), value: placePageModel.info == nil)
        .onChange(of: placePageModel.openToken) { _, _ in
          selectedList = nil
          paneHidden = false
        }
        .onAppear {
          downloadModel.start()
          placePageModel.start()
          bookmarksModel.refresh()
        }
        .toolbar { toolbarContent }
    }
  }

  // MARK: - Overlays

  @ViewBuilder private var navigatorOverlay: some View {
    if showNavigator {
      NavigatorView(
        model: bookmarksModel,
        onSelectList: { list in
          selectedList = list
          paneHidden = false
        },
        onSelectBookmark: { bookmarksModel.showBookmarkOnMap($0) },
        onSelectTrack: { bookmarksModel.showTrackOnMap($0) },
        onHide: { showNavigator = false })
        .transition(.move(edge: .leading))
    }
  }

  @ViewBuilder private var infoOverlay: some View {
    if !paneHidden {
      if let list = selectedList {
        ListInfoView(list: list, onClear: { selectedList = nil }, onHide: { paneHidden = true })
          .transition(.move(edge: .trailing))
      } else if let info = placePageModel.info {
        PlacePageView(
          info: info,
          onClear: { placePageModel.clearSelection() },
          onHide: { paneHidden = true },
          onAddBookmark: {
            OMBookmarksHelper.addBookmarkForCurrentPlace()
            bookmarksModel.refresh()
          })
          .transition(.move(edge: .trailing))
      }
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button { showNavigator.toggle() } label: { Image(systemName: "bookmark") }
        .help("Bookmarks")
    }
    ToolbarItemGroup(placement: .automatic) {
      Menu {
        Toggle("Subway", isOn: Binding(get: { layersModel.subway }, set: layersModel.setSubway))
        Toggle("Isolines", isOn: Binding(get: { layersModel.isolines }, set: layersModel.setIsolines))
        Toggle("Outdoor", isOn: Binding(get: { layersModel.outdoor }, set: layersModel.setOutdoor))
        Toggle("Hiking", isOn: Binding(get: { layersModel.hiking }, set: layersModel.setHiking))
        Toggle("Cycling", isOn: Binding(get: { layersModel.cycling }, set: layersModel.setCycling))
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
        .disabled(!hasInfo)
    }
  }
}

/// Mobile-style "download this area" prompt shown over the map when the region
/// under the viewport is missing, downloading, or failed.
private struct DownloadBanner: View {
  @ObservedObject var model: MapDownloadModel

  var body: some View {
    switch model.status {
    case .notDownloaded, .onDiskOutOfDate:
      banner {
        Button { model.download() } label: {
          Label(actionTitle, systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .shift)
      }
    case .downloading, .inQueue:
      banner {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.status == .inQueue ? "\(model.name) — queued" : "Downloading \(model.name)…")
            .font(.subheadline)
          ProgressView(value: model.progressFraction).frame(width: 220)
        }
        Button("Cancel", role: .cancel) { model.cancel() }
      }
    case .error:
      banner {
        Text("Couldn't download \(model.name)").font(.subheadline)
        Button("Retry") { model.retry() }.buttonStyle(.borderedProminent)
      }
    case .none, .onDisk:
      EmptyView()
    @unknown default:
      EmptyView()
    }
  }

  private var actionTitle: String {
    let verb = model.status == .onDiskOutOfDate ? "Update" : "Download"
    let size = ByteCountFormatter.string(fromByteCount: Int64(model.sizeBytes), countStyle: .file)
    return "\(verb) \(model.name) • \(size)"
  }

  private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 12) { content() }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      .shadow(radius: 8)
  }
}
