import Foundation

/// One row in the maps manager tree. Children are loaded lazily on expansion.
final class MapNode: Identifiable, ObservableObject {
  let id: String
  let name: String
  let expandable: Bool
  let sizeBytes: UInt64

  @Published var status: OMDownloadStatus
  @Published var downloadedBytes: Int64
  @Published var totalBytes: Int64
  @Published var isExpanded: Bool = false
  @Published var children: [MapNode]?

  init(node: OMCountryNode) {
    id = node.countryId
    name = node.name
    expandable = node.expandable
    sizeBytes = node.sizeBytes
    status = node.status
    downloadedBytes = node.downloadedBytes
    totalBytes = node.totalBytes
  }

  var progressFraction: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1.0, Double(downloadedBytes) / Double(totalBytes))
  }
}

/// Backs the Downloads Manager window: a browsable tree of all regions with
/// status and download/delete actions. Independent of the in-map prompt.
final class MapsManagerModel: NSObject, ObservableObject, OMMapsManagerDelegate {
  @Published var roots: [MapNode] = []
  /// Flat list of leaf regions currently OnDisk / OnDiskOutOfDate. Refreshed
  /// whenever the storage delegate fires so the "Downloaded" tab stays current
  /// while a download finishes or a delete completes.
  @Published var downloaded: [MapNode] = []

  private let manager = OMMapsManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.start()
    roots = manager.children(of: "").map(MapNode.init)
    refreshDownloaded()
  }

  func children(of countryId: String) -> [MapNode] {
    manager.children(of: countryId).map(MapNode.init)
  }

  func search(_ query: String) -> [MapNode] {
    manager.search(query).map(MapNode.init)
  }

  func download(_ node: MapNode) { manager.download(node.id) }
  func update(_ node: MapNode) { manager.update(node.id) }
  func delete(_ node: MapNode) { manager.deleteCountry(node.id) }
  func cancel(_ node: MapNode) { manager.cancel(node.id) }

  // MARK: - OMMapsManagerDelegate

  func mapsManagerDidChange() {
    refresh(nodes: roots)
    refreshDownloaded()
  }

  /// Refresh status/progress of already-loaded nodes in place (no full rebuild),
  /// so an in-progress download updates without collapsing the tree.
  private func refresh(nodes: [MapNode]) {
    for node in nodes {
      let fresh = manager.node(for: node.id)
      node.status = fresh.status
      node.downloadedBytes = fresh.downloadedBytes
      node.totalBytes = fresh.totalBytes
      if let children = node.children {
        refresh(nodes: children)
      }
    }
  }

  /// Rebuild the flat downloaded list. Cheap — the engine walk skips
  /// not-downloaded subtrees in practice because we only descend to leaves.
  private func refreshDownloaded() {
    downloaded = manager.downloadedLeafNodes().map(MapNode.init)
  }
}
