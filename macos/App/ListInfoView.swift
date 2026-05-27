import SwiftUI

/// Right-hand info pane content for a selected bookmark list.
struct ListInfoView: View {
  let list: BookmarkGroup
  let onClear: () -> Void
  let onHide: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          detail("Bookmarks", "\(list.bookmarksCount)")
          detail("Tracks", "\(list.trackCount)")
          detail("Visible", list.isVisible ? "Yes" : "No")
          if list.hasDescription, !list.annotation.isEmpty {
            detail("Description", list.annotation)
          }
          if !list.author.isEmpty {
            detail("Author", list.author)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
    }
    .frame(width: 340)
    .background(.regularMaterial)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(list.title).font(.headline)
        Text("List").font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: onHide) { Image(systemName: "sidebar.right") }
        .buttonStyle(.borderless).help("Hide info pane")
      Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(.borderless).help("Clear selection")
    }
    .padding(16)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}
