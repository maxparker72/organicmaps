import Foundation

/// Field-aware substring matcher shared by the tree NavigatorView (in-pane
/// search) and the flat NavigatorTableView. Matches name, description, tags,
/// and region display names — see commit b373f8df62 for the rationale.
enum LibrarySearch {
  static func matchesBookmark(_ bm: Bookmark, query: String) -> Bool {
    if query.isEmpty { return true }
    if bm.bookmarkName.localizedCaseInsensitiveContains(query) { return true }
    if EntityEditor.bookmarkDescription(bm.bookmarkId).localizedCaseInsensitiveContains(query) {
      return true
    }
    for tag in OMBookmarksHelper.tags(forBookmark: bm.bookmarkId)
      where tag.localizedCaseInsensitiveContains(query) { return true }
    for region in OMBookmarksHelper.regions(forBookmark: bm.bookmarkId) {
      if OMBookmarksHelper.displayName(forRegion: region).localizedCaseInsensitiveContains(query) {
        return true
      }
    }
    return false
  }

  static func matchesTrack(_ track: Track, query: String) -> Bool {
    if query.isEmpty { return true }
    if track.trackName.localizedCaseInsensitiveContains(query) { return true }
    if EntityEditor.trackDescription(track.trackId).localizedCaseInsensitiveContains(query) {
      return true
    }
    for tag in OMBookmarksHelper.tags(forTrack: track.trackId)
      where tag.localizedCaseInsensitiveContains(query) { return true }
    for region in OMBookmarksHelper.regions(forTrack: track.trackId) {
      if OMBookmarksHelper.displayName(forRegion: region).localizedCaseInsensitiveContains(query) {
        return true
      }
    }
    return false
  }
}
