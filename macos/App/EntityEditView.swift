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
  /// A track's color as stored, and the palette swatch shown for it. Save writes the
  /// stored color back unless the user picks another swatch, so editing a name
  /// doesn't replace an imported custom color (LIB-06).
  @State private var storedTrackColor: NSColor?
  @State private var loadedSwatch: BookmarkColor?
  @State private var listId: MWMMarkGroupID = 0
  @State private var lists: [BookmarkGroup] = []
  @State private var tags: [String] = []
  @State private var newTag: String = ""
  @StateObject private var tagStore = TagStore()

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
        field("Tags") { tagEditor }
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

  /// Minimal token-field UI: a wrap-style row of removable chips, plus a
  /// TextField that commits on Return. Save persists the working set via
  /// OMBookmarksHelper.setTags. AppKit's NSTokenField is heavier and would
  /// drag in NSViewRepresentable plumbing for marginal benefit at this scope.
  @ViewBuilder private var tagEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !tags.isEmpty {
        WrapHStack(spacing: 4) {
          ForEach(tags, id: \.self) { tag in
            TagChip(tag: tag, onTap: nil, onRemove: { removeTag(tag) })
          }
        }
      }
      HStack(spacing: 6) {
        TextField("Add tag", text: $newTag, prompt: Text("Type to search or add"))
          .textFieldStyle(.roundedBorder)
          .onSubmit { commitNewTag() }
        existingTagsMenu
        if !newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button("Add", action: commitNewTag)
            .controlSize(.small)
        }
      }
    }
  }

  /// Dropdown of tags already in use across the library that aren't already
  /// on this item. Filters by what the user has typed so it doubles as
  /// search: pick a match, or commit the typed value as a new tag.
  @ViewBuilder private var existingTagsMenu: some View {
    let q = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    let suggestions: [String] = tagStore.allTags.filter { existing in
      let onItem = tags.contains { $0.caseInsensitiveCompare(existing) == .orderedSame }
      if onItem { return false }
      return q.isEmpty || existing.localizedCaseInsensitiveContains(q)
    }
    if !suggestions.isEmpty {
      Menu {
        ForEach(suggestions, id: \.self) { existing in
          Button(existing) {
            tags.append(existing)
            newTag = ""
          }
        }
      } label: { Image(systemName: "tag") }
      .menuStyle(.borderlessButton).fixedSize().help("Pick from existing tags")
    }
  }

  private func commitNewTag() {
    let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
      tags.append(trimmed)
    }
    newTag = ""
  }

  private func removeTag(_ tag: String) {
    tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
  }

  private func load() {
    lists = EntityEditor.lists()
    if info.isTrack {
      name = EntityEditor.trackName(info.trackId)
      details = EntityEditor.trackDescription(info.trackId)
      listId = EntityEditor.trackGroup(info.trackId)
      let stored = EntityEditor.trackColor(info.trackId)
      storedTrackColor = stored
      color = BookmarkColor.closest(to: stored)
      loadedSwatch = color
      tags = OMBookmarksHelper.tags(forTrack: info.trackId)
    } else {
      name = EntityEditor.bookmarkName(info.bookmarkId)
      details = EntityEditor.bookmarkDescription(info.bookmarkId)
      color = EntityEditor.bookmarkColor(info.bookmarkId)
      listId = EntityEditor.bookmarkGroup(info.bookmarkId)
      tags = OMBookmarksHelper.tags(forBookmark: info.bookmarkId)
    }
  }

  private func save() {
    // Commit any half-typed tag so the user doesn't lose what's in the field.
    commitNewTag()
    if info.isTrack {
      let trackColor = (color == loadedSwatch ? storedTrackColor : nil) ?? color.nsColor
      EntityEditor.saveTrack(info.trackId, group: listId, title: name, color: trackColor, description: details)
      OMBookmarksHelper.setTags(tags, forTrack: info.trackId)
      // Tracks render via a separate user-line cache; the implicit dirty path
      // doesn't always re-flush the existing tile, so kick the engine.
      OMBookmarksHelper.invalidateUserMarks()
    } else {
      EntityEditor.saveBookmark(info.bookmarkId, group: listId, title: name, color: color, description: details)
      OMBookmarksHelper.setTags(tags, forBookmark: info.bookmarkId)
    }
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
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

/// Minimal flowing HStack: lays children left-to-right, wraps when the row
/// runs out of width. Used by the tag editor so a dozen chips don't
/// overflow horizontally. Built atop SwiftUI's Layout protocol so it sizes
/// correctly inside a ScrollView.
private struct WrapHStack: Layout {
  let spacing: CGFloat

  init(spacing: CGFloat = 4, @ViewBuilder _ content: () -> some View) {
    self.spacing = spacing
  }
  init(spacing: CGFloat = 4) { self.spacing = spacing }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    layout(in: proposal.width ?? .infinity, subviews: subviews).total
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = layout(in: bounds.width, subviews: subviews)
    for (i, frame) in result.frames.enumerated() {
      subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
    }
  }

  private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], total: CGSize) {
    var frames: [CGRect] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var widest: CGFloat = 0
    for sv in subviews {
      let size = sv.sizeThatFits(.unspecified)
      if x > 0 && x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    return (frames, CGSize(width: widest, height: y + rowHeight))
  }
}
