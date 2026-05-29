import Foundation

/// Whether the navigator pane shows the existing tree (lists with expandable
/// items) or a flat sortable Finder-style table of the whole library.
enum NavigatorViewMode: String, CaseIterable, Identifiable {
  case tree
  case table

  var id: String { rawValue }

  /// Persists across launches via UserDefaults, like DataDirectoryManager's
  /// override pattern. The default keeps the existing tree UI so users who
  /// upgrade don't get an unexpected switch.
  static let defaultsKey = "OMNavigatorViewMode"

  static func loadPersisted() -> NavigatorViewMode {
    if let raw = UserDefaults.standard.string(forKey: defaultsKey),
       let mode = NavigatorViewMode(rawValue: raw) {
      return mode
    }
    return .tree
  }

  func persist() {
    UserDefaults.standard.set(rawValue, forKey: NavigatorViewMode.defaultsKey)
  }

  /// Width of the navigator pane in each mode. The table needs more horizontal
  /// space to fit its columns; ContentView consults this when computing where
  /// to anchor overlays that sit to its right.
  var paneWidth: CGFloat {
    switch self {
    case .tree: return 300
    case .table: return 720
    }
  }
}
