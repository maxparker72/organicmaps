import SwiftUI

extension BookmarkColor {
  /// Selectable colors offered in the editor (matches the iOS palette order).
  static let palette: [BookmarkColor] = [
    .red, .pink, .purple, .deepPurple, .blue, .lightBlue, .cyan, .teal,
    .green, .lime, .yellow, .orange, .deepOrange, .brown, .gray, .blueGray,
  ]

  var nsColor: NSColor { NSColor(swiftUIColor) }
}
