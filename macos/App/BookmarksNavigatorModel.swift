import SwiftUI

extension Notification.Name {
  /// Posted when item visibility changes from elsewhere (e.g. the filter window),
  /// so the navigator's eye icons stay in sync.
  static let omItemVisibilityChanged = Notification.Name("omItemVisibilityChanged")
}

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

  private var visibilityObserver: NSObjectProtocol?

  override init() {
    super.init()
    // Cast to the protocol so this resolves to BookmarksObservable.addObserver(_:)
    // rather than NSObject's KVO addObserver(_:forKeyPath:options:context:).
    (manager as any BookmarksObservable).add(self)
    visibilityObserver = NotificationCenter.default.addObserver(
      forName: .omItemVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
      self?.objectWillChange.send()
    }
    if manager.areBookmarksLoaded() {
      refresh()
    } else {
      manager.loadBookmarks()
    }
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
    if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
  }

  func refresh() {
    lists = manager.sortedUserCategories()
  }

  // MARK: - Visibility

  func setVisible(_ list: BookmarkGroup, _ visible: Bool) {
    manager.setCategory(list.categoryId, isVisible: visible)
    refresh()
  }

  func showAll() {
    OMBookmarksHelper.showAllItems()  // also clears any visual filter (bookmarks + tracks)
    manager.setUserCategoriesVisible(true)
    refresh()
  }
  func hideAll() { manager.setUserCategoriesVisible(false); refresh() }

  func setBookmarkVisible(_ id: MWMMarkID, _ visible: Bool) {
    OMBookmarksHelper.setBookmarks([NSNumber(value: id)], visible: visible)
    objectWillChange.send()
  }
  func setTrackVisible(_ id: MWMTrackID, _ visible: Bool) {
    OMBookmarksHelper.setTracks([NSNumber(value: id)], visible: visible)
    objectWillChange.send()
  }

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

  // MARK: - Bulk operations

  /// Delete the union of selected bookmarks and tracks in one edit session.
  func deleteItems(bookmarkIds: [NSNumber], trackIds: [NSNumber]) {
    if !bookmarkIds.isEmpty { OMBookmarksHelper.deleteBookmarks(bookmarkIds) }
    if !trackIds.isEmpty { OMBookmarksHelper.deleteTracks(trackIds) }
    refresh()
  }

  func moveItems(bookmarkIds: [NSNumber], trackIds: [NSNumber], to group: MWMMarkGroupID) {
    if !bookmarkIds.isEmpty { OMBookmarksHelper.moveBookmarks(bookmarkIds, to: group) }
    if !trackIds.isEmpty { OMBookmarksHelper.moveTracks(trackIds, to: group) }
    refresh()
  }

  func setColorForItems(bookmarkIds: [NSNumber], trackIds: [NSNumber], color: BookmarkColor) {
    if !bookmarkIds.isEmpty { OMBookmarksHelper.setBookmarks(bookmarkIds, color: color) }
    if !trackIds.isEmpty { OMBookmarksHelper.setTracks(trackIds, color: color) }
    OMBookmarksHelper.invalidateUserMarks()
    objectWillChange.send()
  }

  func setItemsVisible(bookmarkIds: [NSNumber], trackIds: [NSNumber], visible: Bool) {
    if !bookmarkIds.isEmpty { OMBookmarksHelper.setBookmarks(bookmarkIds, visible: visible) }
    if !trackIds.isEmpty { OMBookmarksHelper.setTracks(trackIds, visible: visible) }
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  /// Add a tag to every selected item (union with each item's existing tags).
  /// `setTags` collapses duplicates and posts `.omTagsChanged`.
  func addTag(_ tag: String, bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    for id in bookmarkIds {
      var existing = OMBookmarksHelper.tags(forBookmark: id)
      if !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        existing.append(trimmed)
        OMBookmarksHelper.setTags(existing, forBookmark: id)
      }
    }
    for id in trackIds {
      var existing = OMBookmarksHelper.tags(forTrack: id)
      if !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        existing.append(trimmed)
        OMBookmarksHelper.setTags(existing, forTrack: id)
      }
    }
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
  }

  func removeTag(_ tag: String, bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) {
    for id in bookmarkIds {
      let existing = OMBookmarksHelper.tags(forBookmark: id)
      let filtered = existing.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
      if filtered.count != existing.count {
        OMBookmarksHelper.setTags(filtered, forBookmark: id)
      }
    }
    for id in trackIds {
      let existing = OMBookmarksHelper.tags(forTrack: id)
      let filtered = existing.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
      if filtered.count != existing.count {
        OMBookmarksHelper.setTags(filtered, forTrack: id)
      }
    }
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
  }

  // MARK: - BookmarksObserver

  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { refresh() }
  func onTrackDeleted(_ trackId: MWMTrackID) { refresh() }
}
