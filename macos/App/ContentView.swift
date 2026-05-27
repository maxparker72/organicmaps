import SwiftUI

struct ContentView: View {
  // Placeholder sidebar sections; real bookmark/track organization comes later.
  private enum SidebarItem: String, CaseIterable, Identifiable {
    case map = "Map"
    case bookmarks = "Bookmarks"
    case tracks = "Tracks"
    var id: String { rawValue }
  }

  @State private var selection: SidebarItem? = .map
  @State private var paneHidden = false
  @StateObject private var downloadModel = MapDownloadModel()
  @StateObject private var layersModel = LayersModel()
  @StateObject private var placePageModel = PlacePageModel()

  var body: some View {
    NavigationSplitView {
      List(SidebarItem.allCases, selection: $selection) { item in
        Text(item.rawValue).tag(item)
      }
      .navigationTitle("Organic Maps")
      .frame(minWidth: 200)
    } detail: {
      MapView()
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
          DownloadBanner(model: downloadModel)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .trailing) {
          if let info = placePageModel.info, !paneHidden {
            PlacePageView(
              info: info,
              onClear: { placePageModel.clearSelection() },
              onHide: { paneHidden = true })
              .transition(.move(edge: .trailing))
          }
        }
        .animation(.easeInOut(duration: 0.2), value: placePageModel.info == nil)
        .animation(.easeInOut(duration: 0.2), value: paneHidden)
        .onChange(of: placePageModel.openToken) { _, _ in paneHidden = false }
        .onAppear {
          downloadModel.start()
          placePageModel.start()
        }
        .toolbar {
          ToolbarItemGroup(placement: .automatic) {
            Button {
              paneHidden.toggle()
            } label: {
              Image(systemName: "info.circle")
            }
            .help(paneHidden ? "Show info pane" : "Hide info pane")
            .disabled(placePageModel.info == nil)

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

            Button {
              OMLocationController.followMyPosition()
            } label: {
              Image(systemName: "location")
            }
            .help("Show my location")

            Button {
              OMMapControls.rotateToNorth()
            } label: {
              Image(systemName: "location.north.line")
            }
            .help("Orient north")
          }
        }
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
        Button {
          model.download()
        } label: {
          Label(actionTitle, systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        // Download the highlighted area without reaching for the mouse.
        .keyboardShortcut(.return, modifiers: .shift)
      }
    case .downloading, .inQueue:
      banner {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.status == .inQueue ? "\(model.name) — queued" : "Downloading \(model.name)…")
            .font(.subheadline)
          ProgressView(value: model.progressFraction)
            .frame(width: 220)
        }
        Button("Cancel", role: .cancel) { model.cancel() }
      }
    case .error:
      banner {
        Text("Couldn't download \(model.name)").font(.subheadline)
        Button("Retry") { model.retry() }
          .buttonStyle(.borderedProminent)
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
    HStack(spacing: 12) {
      content()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(radius: 8)
  }
}
