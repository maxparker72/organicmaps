import Foundation

/// Runs the import-normalization sweep (OMBookmarksHelper.normalizeAllItems)
/// every time the user imports a bookmark file so newly-loaded tracks pick up
/// the standard line width and palette-snapped colors.
final class ImportNormalizer: NSObject, ObservableObject, BookmarksObserver {
  override init() {
    super.init()
    (BookmarksManager.shared() as any BookmarksObservable).add(self)
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
  }

  func onBookmarksFileLoadSuccess() {
    OMBookmarksHelper.normalizeAllItems()
  }
}
