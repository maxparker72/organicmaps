import SwiftUI

/// Right-hand info pane content for a selected bookmark list, with inline edit.
struct ListInfoView: View {
  let list: BookmarkGroup
  let onClear: () -> Void
  let onHide: () -> Void
  let onChanged: () -> Void
  let onDeleted: () -> Void

  @State private var editing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if editing {
        editForm
      } else {
        readContent
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
      if !editing {
        Button { editing = true } label: { Image(systemName: "pencil") }
          .buttonStyle(.borderless).help("Edit list")
      }
      Button(action: onHide) { Image(systemName: "sidebar.right") }
        .buttonStyle(.borderless).help("Hide info pane")
      Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(.borderless).help("Clear selection")
    }
    .padding(16)
  }

  private var readContent: some View {
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
        if !trackStats.isEmpty {
          Divider()
          section("Aggregate statistics") { TrackStatsView(mode: .aggregate(trackStats)) }
        }
        Divider()
        Menu {
          Button("KMZ") { export(.kmz) }
          Button("KML") { export(.kml) }
          Button("GPX") { export(.gpx) }
          Button("GeoJSON") { export(.geoJson) }
        } label: {
          Label("Export…", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
  }

  // Cached so the (potentially expensive) per-track stats lookup isn't
  // repeated on every body re-evaluation.
  private var trackStats: [OMTrackStats] {
    list.tracks.compactMap { OMBookmarksHelper.trackStats(forTrack: $0.trackId) }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      content()
    }
  }

  private func export(_ fileType: FileType) {
    BookmarkFiles.exportList(list.categoryId, fileType: fileType, suggestedName: list.title)
  }

  private var editForm: some View {
    ListEditView(
      listId: list.categoryId,
      onSave: { editing = false; onChanged() },
      onCancel: { editing = false },
      onDelete: { editing = false; onDeleted() })
  }

  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}

/// Inline list editor: name, description, colour applied to all items, delete.
private struct ListEditView: View {
  let listId: MWMMarkGroupID
  let onSave: () -> Void
  let onCancel: () -> Void
  let onDelete: () -> Void

  @State private var name = ""
  @State private var details = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        field("Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
        field("Description") {
          TextField("Description", text: $details, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(3...6)
        }
        Divider()
        HStack {
          Button("Delete List", role: .destructive) {
            EntityEditor.deleteList(listId)
            onDelete()
          }
          Spacer()
          Button("Cancel", action: onCancel)
          Button("Save") {
            EntityEditor.saveList(listId, name: name, description: details)
            onSave()
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(16)
    }
    .onAppear {
      name = EntityEditor.listName(listId)
      details = EntityEditor.listDescription(listId)
    }
  }

  private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      content()
    }
  }
}
