import SwiftUI

struct MapsManagerView: View {
  enum Scope: String, CaseIterable, Identifiable {
    case all = "All Regions"
    case downloaded = "Downloaded"
    var id: String { rawValue }
  }

  @StateObject private var model = MapsManagerModel()
  @State private var searchText = ""
  @State private var results: [MapNode] = []
  @State private var scope: Scope = .all

  /// Downloaded-mode rows, filtered by the current search text. Cheap —
  /// the downloaded list is short relative to the full tree.
  private var visibleDownloaded: [MapNode] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return model.downloaded }
    return model.downloaded.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) ||
      $0.id.localizedCaseInsensitiveContains(trimmed)
    }
  }

  private var downloadedSummary: String {
    let count = model.downloaded.count
    let bytes = model.downloaded.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    return "\(count) \(count == 1 ? "map" : "maps") · \(size)"
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("", selection: $scope) {
        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 6)

      Group {
        switch scope {
        case .all: allRegionsList
        case .downloaded: downloadedList
        }
      }
    }
    .frame(minWidth: 480, minHeight: 440)
    .navigationTitle("Download Maps")
    .searchable(text: $searchText, prompt: scope == .all ? "Search regions" : "Filter downloaded")
    .onChange(of: searchText) { _, query in
      if scope == .all {
        results = query.count >= 2 ? model.search(query) : []
      }
    }
    .onChange(of: scope) { _, _ in
      // Reset the All-mode search results when flipping back; downloaded-mode
      // filters live off model.downloaded so it doesn't need its own buffer.
      results = []
    }
  }

  @ViewBuilder private var allRegionsList: some View {
    if searchText.isEmpty {
      List {
        ForEach(model.roots) { node in
          MapNodeRow(node: node, model: model)
        }
      }
    } else {
      List(results) { node in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(node.name.isEmpty ? node.id : node.name)
            Text(node.id).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          NodeActionButton(node: node, model: model)
        }
      }
    }
  }

  @ViewBuilder private var downloadedList: some View {
    if model.downloaded.isEmpty {
      VStack(spacing: 6) {
        Image(systemName: "tray")
          .font(.system(size: 32, weight: .light))
          .foregroundStyle(.secondary)
        Text("No maps downloaded yet")
          .font(.headline)
        Text("Switch to All Regions to find and download maps.")
          .font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(spacing: 0) {
        HStack {
          Text(downloadedSummary)
            .font(.subheadline).foregroundStyle(.secondary)
          Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        Divider()
        List(visibleDownloaded) { node in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(node.name.isEmpty ? node.id : node.name)
              Text(ByteCountFormatter.string(fromByteCount: Int64(node.sizeBytes), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            NodeActionButton(node: node, model: model)
          }
        }
      }
    }
  }
}

private struct MapNodeRow: View {
  @ObservedObject var node: MapNode
  let model: MapsManagerModel

  var body: some View {
    if node.expandable {
      DisclosureGroup(isExpanded: $node.isExpanded) {
        if let children = node.children {
          ForEach(children) { MapNodeRow(node: $0, model: model) }
        }
      } label: {
        rowContent
      }
      .onChange(of: node.isExpanded) { _, expanded in
        if expanded && node.children == nil {
          node.children = model.children(of: node.id)
        }
      }
    } else {
      rowContent
    }
  }

  private var rowContent: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(node.name.isEmpty ? node.id : node.name)
        if node.status == .downloading || node.status == .inQueue {
          ProgressView(value: node.progressFraction).frame(width: 160)
        } else if node.sizeBytes > 0 {
          Text(ByteCountFormatter.string(fromByteCount: Int64(node.sizeBytes), countStyle: .file))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      NodeActionButton(node: node, model: model)
    }
  }
}

/// The per-region action (download / update / delete / cancel / retry), shared
/// by the tree rows and the search results. Works for both groups and leaves.
private struct NodeActionButton: View {
  @ObservedObject var node: MapNode
  let model: MapsManagerModel

  var body: some View {
    switch node.status {
    case .onDisk:
      Button { model.delete(node) } label: { Image(systemName: "trash") }
        .help("Remove downloaded map")
    case .onDiskOutOfDate:
      Button("Update") { model.update(node) }
        .help("Update to the latest map data")
    case .notDownloaded:
      Button { model.download(node) } label: { Image(systemName: "arrow.down.circle") }
        .help(node.expandable ? "Download all regions" : "Download")
    case .downloading, .inQueue:
      Button(role: .cancel) { model.cancel(node) } label: { Image(systemName: "xmark.circle") }
        .help("Cancel")
    case .error:
      Button("Retry") { model.download(node) }
    case .none:
      EmptyView()
    @unknown default:
      EmptyView()
    }
  }
}
