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
  @StateObject private var downloadModel = MapDownloadModel()

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
        .onAppear { downloadModel.start() }
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
