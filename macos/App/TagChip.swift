import SwiftUI

extension String {
  /// Deterministic mapping from a tag string to one of the 16 palette colours.
  /// djb2 hash → modular index. Stable across launches and re-installs because
  /// it doesn't depend on Swift's randomized String.hashValue.
  var tagPaletteColor: BookmarkColor {
    var h = 5381
    for scalar in unicodeScalars {
      h = ((h &* 33) &+ Int(scalar.value)) & 0x7fffffff
    }
    let palette = BookmarkColor.palette
    return palette[h % palette.count]
  }
}

/// One coloured pill rendering a single tag. Variants:
/// - display-only (both closures nil) for navigator rows that already eat
///   their click for selection;
/// - tap-to-search (`onTap` non-nil) for the table view and similar spots
///   where the chip is the entire hit target;
/// - editor (`onRemove` non-nil) for the inspector's token editor.
struct TagChip: View {
  let tag: String
  var onTap: (() -> Void)? = nil
  var onRemove: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 4) {
      Circle().fill(tag.tagPaletteColor.swiftUIColor).frame(width: 5, height: 5)
      Text(tag).font(.caption2).lineLimit(1)
      if let onRemove {
        Button(action: onRemove) {
          Image(systemName: "xmark.circle.fill").font(.caption2)
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(tag.tagPaletteColor.swiftUIColor.opacity(0.2), in: Capsule())
    .contentShape(Capsule())
    .onTapGesture { onTap?() }
  }
}

/// Compact row of tags with overflow indicator. Used under bookmark/track
/// rows in the navigator and in the Tags column of the column view.
struct TagChipRow: View {
  let tags: [String]
  var limit: Int = 3
  var onTap: ((String) -> Void)? = nil

  var body: some View {
    if tags.isEmpty {
      EmptyView()
    } else {
      HStack(spacing: 4) {
        ForEach(Array(tags.prefix(limit)), id: \.self) { tag in
          TagChip(tag: tag,
                  onTap: onTap.map { fn in { fn(tag) } },
                  onRemove: nil)
        }
        if tags.count > limit {
          Text("+\(tags.count - limit)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
