import SwiftUI

/// Inline edit form in the info pane for a selected bookmark or track:
/// name, description, color and owning list, with save / discard / delete.
struct EntityEditView: View {
  let info: OMPlaceInfo
  let onSave: () -> Void
  let onCancel: () -> Void
  let onDelete: () -> Void

  @State private var name = ""
  @State private var details = ""
  @State private var color: BookmarkColor = .red
  @State private var listId: MWMMarkGroupID = 0
  @State private var lists: [BookmarkGroup] = []

  private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 8)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        field("Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
        field("Description") {
          TextField("Description", text: $details, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(3...6)
        }
        field("Color") {
          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(BookmarkColor.palette, id: \.rawValue) { swatch in
              Circle().fill(swatch.swiftUIColor).frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.primary, lineWidth: swatch == color ? 2 : 0))
                .onTapGesture { color = swatch }
            }
          }
        }
        field("List") {
          Picker("List", selection: $listId) {
            ForEach(lists, id: \.categoryId) { Text($0.title).tag($0.categoryId) }
          }
          .labelsHidden()
        }
        Divider()
        HStack {
          Button("Delete", role: .destructive) { delete() }
          Spacer()
          Button("Cancel", action: onCancel)
          Button("Save") { save() }.buttonStyle(.borderedProminent)
        }
      }
      .padding(16)
    }
    .onAppear(perform: load)
  }

  private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      content()
    }
  }

  private func load() {
    lists = EntityEditor.lists()
    if info.isTrack {
      name = EntityEditor.trackName(info.trackId)
      details = EntityEditor.trackDescription(info.trackId)
      listId = EntityEditor.trackGroup(info.trackId)
    } else {
      name = EntityEditor.bookmarkName(info.bookmarkId)
      details = EntityEditor.bookmarkDescription(info.bookmarkId)
      color = EntityEditor.bookmarkColor(info.bookmarkId)
      listId = EntityEditor.bookmarkGroup(info.bookmarkId)
    }
  }

  private func save() {
    if info.isTrack {
      EntityEditor.saveTrack(info.trackId, group: listId, title: name, color: color.nsColor, description: details)
    } else {
      EntityEditor.saveBookmark(info.bookmarkId, group: listId, title: name, color: color, description: details)
    }
    FrameworkHelper.updatePlacePageData()
    onSave()
  }

  private func delete() {
    if info.isTrack {
      EntityEditor.deleteTrack(info.trackId)
    } else {
      EntityEditor.deleteBookmark(info.bookmarkId)
    }
    onDelete()
  }
}
