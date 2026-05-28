import SwiftUI

extension BookmarkColor {
  /// Selectable colors offered in the editor (matches the iOS palette order).
  static let palette: [BookmarkColor] = [
    .red, .pink, .purple, .deepPurple, .blue, .lightBlue, .cyan, .teal,
    .green, .lime, .yellow, .orange, .deepOrange, .brown, .gray, .blueGray,
  ]

  // Explicit sRGB components so the engine's getRed:green:blue: can always read
  // them. Dynamic system colors (from SwiftUI Color.red etc.) live in a
  // catalogue colorspace and would raise NSInvalidArgumentException.
  var rgbComponents: (CGFloat, CGFloat, CGFloat) {
    switch self {
    case .red: return (0.95, 0.20, 0.20)
    case .pink: return (1.00, 0.40, 0.60)
    case .purple: return (0.65, 0.30, 0.85)
    case .deepPurple: return (0.45, 0.25, 0.75)
    case .blue: return (0.15, 0.50, 0.95)
    case .lightBlue: return (0.30, 0.70, 0.95)
    case .cyan: return (0.20, 0.85, 0.95)
    case .teal: return (0.10, 0.65, 0.65)
    case .green: return (0.30, 0.75, 0.35)
    case .lime: return (0.65, 0.85, 0.20)
    case .yellow: return (0.95, 0.85, 0.20)
    case .orange: return (1.00, 0.60, 0.20)
    case .deepOrange: return (1.00, 0.45, 0.25)
    case .brown: return (0.55, 0.35, 0.25)
    case .gray: return (0.55, 0.55, 0.55)
    case .blueGray: return (0.45, 0.55, 0.60)
    default: return (0.5, 0.5, 0.5)
    }
  }

  var nsColor: NSColor {
    let (r, g, b) = rgbComponents
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
  }

  /// Maps an arbitrary NSColor (e.g. a track's stored colour) to the nearest
  /// palette entry by RGB distance, so the editor reflects the current colour.
  static func closest(to color: NSColor) -> BookmarkColor {
    let target = color.usingColorSpace(.sRGB) ?? color
    let r = target.redComponent, g = target.greenComponent, b = target.blueComponent
    return BookmarkColor.palette.min(by: { lhs, rhs in
      let (lr, lg, lb) = lhs.rgbComponents
      let (rr, rg, rb) = rhs.rgbComponents
      return (lr-r)*(lr-r) + (lg-g)*(lg-g) + (lb-b)*(lb-b)
           < (rr-r)*(rr-r) + (rg-g)*(rg-g) + (rb-b)*(rb-b)
    }) ?? .red
  }

  var displayName: String {
    switch self {
    case .red: return "Red"
    case .pink: return "Pink"
    case .purple: return "Purple"
    case .deepPurple: return "Deep Purple"
    case .blue: return "Blue"
    case .lightBlue: return "Light Blue"
    case .cyan: return "Cyan"
    case .teal: return "Teal"
    case .green: return "Green"
    case .lime: return "Lime"
    case .yellow: return "Yellow"
    case .orange: return "Orange"
    case .deepOrange: return "Deep Orange"
    case .brown: return "Brown"
    case .gray: return "Gray"
    case .blueGray: return "Blue Gray"
    default: return "None"
    }
  }
}
