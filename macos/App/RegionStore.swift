import Foundation

/// In-memory directory of all storage regions (countries / MWM sub-regions)
/// that any bookmark or track currently lives in. Region IDs are the engine's
/// CountryId strings (e.g. "United States_California"); display names come
/// from OMBookmarksHelper.displayName(forRegion:).
final class RegionStore: NSObject, ObservableObject, BookmarksObserver {
  @Published private(set) var allRegions: [String] = []

  private var manager: BookmarksManager { BookmarksManager.shared() }
  private var visibilityObserver: NSObjectProtocol?

  override init() {
    super.init()
    (manager as any BookmarksObservable).add(self)
    // Visibility toggles don't change which regions exist, but new items
    // appearing after a filter/show-all do — keep in sync.
    visibilityObserver = NotificationCenter.default.addObserver(
      forName: .omItemVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
      self?.refresh()
    }
    if manager.areBookmarksLoaded() { refresh() }
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
    if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
  }

  func refresh() {
    var seen = Set<String>()
    for list in manager.sortedUserCategories() {
      for bm in list.bookmarks {
        for region in OMBookmarksHelper.regions(forBookmark: bm.bookmarkId) { seen.insert(region) }
      }
      for tr in list.tracks {
        for region in OMBookmarksHelper.regions(forTrack: tr.trackId) { seen.insert(region) }
      }
    }
    allRegions = seen.sorted {
      OMBookmarksHelper.displayName(forRegion: $0).localizedCaseInsensitiveCompare(
        OMBookmarksHelper.displayName(forRegion: $1)) == .orderedAscending
    }
  }

  // MARK: - BookmarksObserver
  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { refresh() }
  func onTrackDeleted(_ trackId: MWMTrackID) { refresh() }
}
