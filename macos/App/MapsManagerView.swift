import SwiftUI

struct MapsManagerView: View {
  @StateObject private var model = MapsManagerModel()
  @State private var searchText = ""
  @State private var results: [MapNode] = []

  var body: some View {
    Group {
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
    .frame(minWidth: 480, minHeight: 440)
    .navigationTitle("Download Maps")
    .searchable(text: $searchText, prompt: "Search regions")
    .onChange(of: searchText) { _, query in
      results = query.count >= 2 ? model.search(query) : []
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
