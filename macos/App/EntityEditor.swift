import AppKit

/// Thin wrapper over BookmarksManager for editing/deleting bookmarks, tracks and
/// lists from the info pane. Keeps the SwiftUI views free of CoreApi specifics.
enum EntityEditor {
  private static var manager: BookmarksManager { BookmarksManager.shared() }

  static func lists() -> [BookmarkGroup] { manager.sortedUserCategories() }

  @discardableResult
  static func createList(_ name: String) -> MWMMarkGroupID {
    manager.createCategory(withName: name)
  }

  // MARK: - Bookmarks

  static func bookmarkName(_ id: MWMMarkID) -> String { manager.bookmark(withId: id).bookmarkName }
  static func bookmarkColor(_ id: MWMMarkID) -> NSColor { manager.bookmark(withId: id).bookmarkColor }
  static func bookmarkDescription(_ id: MWMMarkID) -> String { manager.description(forBookmarkId: id) }
  static func bookmarkGroup(_ id: MWMMarkID) -> MWMMarkGroupID { manager.category(forBookmarkId: id).categoryId }

  static func saveBookmark(_ id: MWMMarkID, group: MWMMarkGroupID, title: String,
                           color: NSColor, description: String) {
    manager.updateBookmark(id, setGroupId: group, title: title, color: color, description: description)
  }

  static func deleteBookmark(_ id: MWMMarkID) { manager.deleteBookmark(id) }

  // MARK: - Tracks

  static func trackName(_ id: MWMTrackID) -> String { manager.track(withId: id).trackName }
  static func trackColor(_ id: MWMTrackID) -> NSColor { manager.track(withId: id).trackColor }
  static func trackDescription(_ id: MWMTrackID) -> String { manager.description(forTrackId: id) }
  static func trackGroup(_ id: MWMTrackID) -> MWMMarkGroupID { manager.category(forTrackId: id).categoryId }

  static func saveTrack(_ id: MWMTrackID, group: MWMMarkGroupID, title: String,
                        color: NSColor, description: String) {
    manager.updateTrack(id, setGroupId: group, color: color, title: title, description: description)
  }

  static func deleteTrack(_ id: MWMTrackID) { manager.deleteTrack(id) }

  // MARK: - Lists

  static func listName(_ id: MWMMarkGroupID) -> String { manager.getCategoryName(id) }
  static func listDescription(_ id: MWMMarkGroupID) -> String { manager.getCategoryDescription(id) }

  static func saveList(_ id: MWMMarkGroupID, name: String, description: String) {
    manager.setCategory(id, name: name)
    manager.setCategory(id, description: description)
  }

  static func deleteList(_ id: MWMMarkGroupID) { manager.deleteCategory(id) }
}
