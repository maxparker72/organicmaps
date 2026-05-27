import SwiftUI

extension BookmarkColor {
  var swiftUIColor: Color {
    switch self {
    case .red: return .red
    case .blue: return .blue
    case .purple, .deepPurple: return .purple
    case .yellow: return .yellow
    case .pink: return .pink
    case .brown: return .brown
    case .green, .lime: return .green
    case .orange, .deepOrange: return .orange
    case .lightBlue, .cyan: return .cyan
    case .teal: return .teal
    case .gray, .blueGray: return .gray
    default: return .secondary
    }
  }
}

/// Drives the bookmarks navigator from CoreApi's BookmarksManager and keeps it
/// in sync via the bookmarks observer.
final class BookmarksNavigatorModel: NSObject, ObservableObject, BookmarksObserver {
  @Published var lists: [BookmarkGroup] = []

  private var manager: BookmarksManager { BookmarksManager.shared() }

  override init() {
    super.init()
    // Cast to the protocol so this resolves to BookmarksObservable.addObserver(_:)
    // rather than NSObject's KVO addObserver(_:forKeyPath:options:context:).
    (manager as any BookmarksObservable).add(self)
    if manager.areBookmarksLoaded() {
      refresh()
    } else {
      manager.loadBookmarks()
    }
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
  }

  func refresh() {
    lists = manager.sortedUserCategories()
  }

  // MARK: - Visibility

  func setVisible(_ list: BookmarkGroup, _ visible: Bool) {
    manager.setCategory(list.categoryId, isVisible: visible)
    refresh()
  }

  func showAll() { manager.setUserCategoriesVisible(true); refresh() }
  func hideAll() { manager.setUserCategoriesVisible(false); refresh() }

  func createList(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    manager.createCategory(withName: trimmed)
    refresh()
  }

  // MARK: - Show on map

  func showBookmarkOnMap(_ id: MWMMarkID) { FrameworkHelper.showBookmark(id) }
  func showTrackOnMap(_ id: MWMTrackID) { FrameworkHelper.showTrack(id) }

  // MARK: - Delete / move

  func deleteBookmark(_ id: MWMMarkID) { manager.deleteBookmark(id); refresh() }
  func deleteTrack(_ id: MWMTrackID) { manager.deleteTrack(id); refresh() }
  func deleteList(_ id: MWMMarkGroupID) { manager.deleteCategory(id); refresh() }
  func moveBookmark(_ id: MWMMarkID, to group: MWMMarkGroupID) { manager.moveBookmark(id, toGroupId: group); refresh() }
  func moveTrack(_ id: MWMTrackID, to group: MWMMarkGroupID) { manager.moveTrack(id, toGroupId: group); refresh() }

  // MARK: - BookmarksObserver

  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { refresh() }
  func onTrackDeleted(_ trackId: MWMTrackID) { refresh() }
}
