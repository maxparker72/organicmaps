import SwiftUI

/// Bulk-operation context menu. Used by both the tree (NavigatorView) and
/// table (NavigatorTableView) right-click menus, and by single-row
/// right-clicks too — a single item is just a one-item batch, so the same
/// Move / Set color / Add tag / Add to project / Show / Hide / Delete
/// surfaces apply uniformly. The caller passes whichever ids should be
/// acted on: the full navigator selection when 2+ are selected and the
/// clicked row is part of it, otherwise just the clicked row's id.
///
/// Selection is still injected because the Delete path runs through
/// ContentView's shared confirmationDialog, which reads from
/// NavigatorSelectionModel — the menu briefly seeds the selection with the
/// target ids so the dialog's perform-delete acts on the right items.
struct BulkContextMenu: View {
  @ObservedObject var selection: NavigatorSelectionModel
  @ObservedObject var model: BookmarksNavigatorModel
  @ObservedObject var tagStore: TagStore
  @ObservedObject var projectsModel: ProjectModel
  let bookmarkIds: [MWMMarkID]
  let trackIds: [MWMTrackID]

  private var bmNumbers: [NSNumber] { bookmarkIds.map { NSNumber(value: $0) } }
  private var trNumbers: [NSNumber] { trackIds.map { NSNumber(value: $0) } }
  private var totalCount: Int { bookmarkIds.count + trackIds.count }
  private var deleteLabel: String {
    "Delete \(totalCount) \(totalCount == 1 ? "item" : "items")…"
  }

  var body: some View {
    Menu("Move to") {
      ForEach(model.lists, id: \.categoryId) { list in
        Button(list.title) {
          model.moveItems(bookmarkIds: bmNumbers, trackIds: trNumbers, to: list.categoryId)
        }
      }
    }
    // Plain-text items: native macOS context-menu submenus template-tint
    // every NSMenuItem image to the system text colour, so a SwiftUI Label
    // icon would render black regardless of foregroundStyle. The inspector's
    // Set Color uses a popover swatch grid for that reason; here we keep
    // the names so the action is still labelled.
    Menu("Set color") {
      ForEach(BookmarkColor.palette, id: \.self) { color in
        Button(color.displayName) {
          model.setColorForItems(bookmarkIds: bmNumbers,
                                 trackIds: trNumbers,
                                 color: color)
        }
      }
    }
    Menu("Add tag") {
      if tagStore.allTags.isEmpty {
        Text("No tags yet").foregroundStyle(.secondary)
      } else {
        ForEach(tagStore.allTags, id: \.self) { tag in
          Button(tag) {
            model.addTag(tag, bookmarkIds: bookmarkIds, trackIds: trackIds)
          }
        }
      }
    }
    Menu("Add to project") {
      if projectsModel.projects.isEmpty {
        Text("No projects yet").foregroundStyle(.secondary)
      } else {
        ForEach(projectsModel.projects) { project in
          Button(project.name) {
            for id in bookmarkIds { projectsModel.addBookmark(id, to: project) }
            for id in trackIds { projectsModel.addTrack(id, to: project) }
          }
        }
      }
    }
    Divider()
    Button("Show") {
      model.setItemsVisible(bookmarkIds: bmNumbers, trackIds: trNumbers, visible: true)
    }
    Button("Hide") {
      model.setItemsVisible(bookmarkIds: bmNumbers, trackIds: trNumbers, visible: false)
    }
    Divider()
    Button(deleteLabel, role: .destructive) {
      // ContentView's confirmationDialog watches pendingBulkDelete and reads
      // from navSelection on confirm. Seed the selection with these ids so a
      // right-click on a row that wasn't already in a multi-selection still
      // deletes the right thing.
      var items: Set<NavSelection> = []
      for id in bookmarkIds { items.insert(.bookmark(id)) }
      for id in trackIds { items.insert(.track(id)) }
      selection.set(items)
      selection.pendingBulkDelete = true
    }
  }
}
