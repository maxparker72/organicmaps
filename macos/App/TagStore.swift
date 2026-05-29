import Foundation

extension Notification.Name {
  /// Posted whenever a bookmark or track's tag set changes. Sources:
  /// add/remove project membership, edit raw tags, project deletion.
  static let omTagsChanged = Notification.Name("omTagsChanged")
}

/// In-memory directory of all tag values currently present across bookmarks
/// and tracks. The filter builder reads `allTags` for its tag-value dropdown.
/// Cheap full rescan on change events; user libraries are small enough that
/// a more sophisticated inverse index isn't worth the complexity for v1.
final class TagStore: NSObject, ObservableObject, BookmarksObserver {
  @Published private(set) var allTags: [String] = []

  private var manager: BookmarksManager { BookmarksManager.shared() }
  private var tagsChangedObserver: NSObjectProtocol?

  override init() {
    super.init()
    (manager as any BookmarksObservable).add(self)
    tagsChangedObserver = NotificationCenter.default.addObserver(
      forName: .omTagsChanged, object: nil, queue: .main) { [weak self] _ in
      self?.refresh()
    }
    if manager.areBookmarksLoaded() { refresh() }
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
    if let tagsChangedObserver { NotificationCenter.default.removeObserver(tagsChangedObserver) }
  }

  func refresh() {
    var seen = Set<String>()
    for list in manager.sortedUserCategories() {
      for bm in list.bookmarks {
        for tag in OMBookmarksHelper.tags(forBookmark: bm.bookmarkId) { seen.insert(tag) }
      }
      for tr in list.tracks {
        for tag in OMBookmarksHelper.tags(forTrack: tr.trackId) { seen.insert(tag) }
      }
    }
    allTags = seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  // MARK: - BookmarksObserver
  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { refresh() }
  func onTrackDeleted(_ trackId: MWMTrackID) { refresh() }
}
