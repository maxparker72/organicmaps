import SwiftUI

/// Bulk-operation context menu shown when 2+ navigator rows are selected.
/// Used by both the tree (NavigatorView) and table (NavigatorTableView)
/// presentations so they share identical behaviour and stay in lock-step.
struct BulkContextMenu: View {
  @ObservedObject var selection: NavigatorSelectionModel
  @ObservedObject var model: BookmarksNavigatorModel
  @ObservedObject var tagStore: TagStore
  @ObservedObject var projectsModel: ProjectModel

  var body: some View {
    Menu("Move to") {
      ForEach(model.lists, id: \.categoryId) { list in
        Button(list.title) {
          model.moveItems(bookmarkIds: selection.bookmarkNSNumbers,
                          trackIds: selection.trackNSNumbers,
                          to: list.categoryId)
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
          model.setColorForItems(bookmarkIds: selection.bookmarkNSNumbers,
                                 trackIds: selection.trackNSNumbers,
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
            model.addTag(tag, bookmarkIds: selection.bookmarkIds, trackIds: selection.trackIds)
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
            for id in selection.bookmarkIds { projectsModel.addBookmark(id, to: project) }
            for id in selection.trackIds { projectsModel.addTrack(id, to: project) }
          }
        }
      }
    }
    Divider()
    Button("Show") {
      model.setItemsVisible(bookmarkIds: selection.bookmarkNSNumbers,
                            trackIds: selection.trackNSNumbers, visible: true)
    }
    Button("Hide") {
      model.setItemsVisible(bookmarkIds: selection.bookmarkNSNumbers,
                            trackIds: selection.trackNSNumbers, visible: false)
    }
    Divider()
    Button("Delete \(selection.count) items…", role: .destructive) {
      // ContentView's confirmationDialog observes pendingBulkDelete and
      // performs the actual delete on confirm — context-menu actions
      // can't host a confirmation themselves.
      selection.pendingBulkDelete = true
    }
  }
}
