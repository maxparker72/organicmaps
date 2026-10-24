import Foundation

/// After each bookmark file import, gives bookmarks that have no palette color the
/// nearest palette entry (OMBookmarksHelper.assignPaletteColorsToUncoloredBookmarks).
/// It never touches track colors or widths: imports keep their styling (D-09, LIB-06).
/// The full normalizeAllItems sweep is only run from the File menu.
final class ImportNormalizer: NSObject, ObservableObject, BookmarksObserver {
  override init() {
    super.init()
    (BookmarksManager.shared() as any BookmarksObservable).add(self)
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
  }

  func onBookmarksFileLoadSuccess() {
    // The engine fires this callback on the Gui thread *before* the matching
    // CreateCategories task runs, so the just-loaded file's items aren't in
    // m_categories yet. Hop one runloop tick so the repair sees them.
    DispatchQueue.main.async {
      let modified = OMBookmarksHelper.assignPaletteColorsToUncoloredBookmarks()
      // Tell the navigator to re-render so rows pick up the new colors.
      if modified > 0 {
        NotificationCenter.default.post(name: .omBookmarkItemsChanged, object: nil)
      }
    }
  }
}
