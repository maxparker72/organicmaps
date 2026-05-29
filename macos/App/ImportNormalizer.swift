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
    // The engine fires this callback on the Gui thread *before* the matching
    // CreateCategories task runs — so the just-loaded file's items aren't in
    // m_categories yet. Hop one runloop tick so normalization sees them and
    // their colours are palette-snapped on first paint (otherwise the
    // navigator row and the map render show drifted colours until the user
    // re-saves the bookmark by hand).
    DispatchQueue.main.async {
      OMBookmarksHelper.normalizeAllItems()
    }
  }
}
