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
  @State private var color: BookmarkColor = .red

  private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        field("Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
        field("Description") {
          TextField("Description", text: $details, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(3...6)
        }
        field("Color (all items)") {
          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BookmarkColor.palette, id: \.rawValue) { swatch in
              Circle().fill(swatch.swiftUIColor).frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.primary, lineWidth: swatch == color ? 2 : 0))
                .onTapGesture { color = swatch }
            }
          }
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
            EntityEditor.saveList(listId, name: name, description: details, color: color)
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
