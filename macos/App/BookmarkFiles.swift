import AppKit
import UniformTypeIdentifiers

/// Import/export of bookmark files (KML/KMZ/GPX/GeoJSON) using native panels.
enum BookmarkFiles {
  private static var manager: BookmarksManager { BookmarksManager.shared() }

  static let importContentTypes: [UTType] = {
    ["kml", "kmz", "gpx", "geojson", "json"].compactMap { UTType(filenameExtension: $0) }
  }()

  /// Load a bookmark/track file into the manager.
  static func load(_ url: URL) {
    manager.loadBookmarkFile(url)
  }

  /// Prompt for one or more files to import.
  static func runImportPanel() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = importContentTypes
    panel.prompt = "Import"
    if panel.runModal() == .OK {
      for url in panel.urls { load(url) }
    }
  }

  /// Export a list: build the archive, then let the user choose where to save it.
  static func exportList(_ id: MWMMarkGroupID, fileType: FileType, suggestedName: String) {
    manager.shareCategory(id, fileType: fileType) { status, url in
      guard status == .success, let url else { return }
      save(temporaryURL: url, suggestedName: suggestedName, ext: url.pathExtension)
    }
  }

  static func exportTrack(_ id: MWMTrackID, fileType: FileType, suggestedName: String) {
    manager.shareTrack(id, fileType: fileType) { status, url in
      guard status == .success, let url else { return }
      save(temporaryURL: url, suggestedName: suggestedName, ext: url.pathExtension)
    }
  }

  private static func save(temporaryURL: URL, suggestedName: String, ext: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(suggestedName).\(ext)"
    if let type = UTType(filenameExtension: ext) {
      panel.allowedContentTypes = [type]
    }
    if panel.runModal() == .OK, let destination = panel.url {
      try? FileManager.default.removeItem(at: destination)
      try? FileManager.default.copyItem(at: temporaryURL, to: destination)
    }
    manager.finishSharing()
  }
}
