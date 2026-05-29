import Foundation

/// One selectable item in the navigator. Bookmark and track IDs are globally
/// unique within `kml`, so cross-list multi-selection is well-defined.
enum NavSelection: Hashable {
  case bookmark(MWMMarkID)
  case track(MWMTrackID)
}

/// Selection state for the bookmarks navigator. Lives alongside the engine's
/// own place-page selection: a single-row click still routes through the
/// engine (so the map highlights the item), but Cmd/Shift-click builds a
/// parallel set used by the bulk-action context menu and the multi-selection
/// inspector. When 2+ items are selected, ContentView swaps the right pane
/// to MultiSelectionInspectorView and tells the engine to deactivate its
/// own selection so the two don't fight for the pane.
final class NavigatorSelectionModel: ObservableObject {
  @Published private(set) var selection: Set<NavSelection> = []

  /// The previous single-click target. Shift-click range-selects from this
  /// anchor to the new item. Reset on plain click.
  private(set) var anchor: NavSelection? = nil

  // MARK: - Mutations

  /// Plain click: selection becomes exactly this one item.
  func replace(with item: NavSelection) {
    selection = [item]
    anchor = item
  }

  /// Cmd-click: toggle membership without affecting the rest.
  func toggle(_ item: NavSelection) {
    if selection.contains(item) {
      selection.remove(item)
      if anchor == item { anchor = selection.first }
    } else {
      selection.insert(item)
      anchor = item
    }
  }

  /// Shift-click: select every item between the anchor and `item` in
  /// `ordered`. If the anchor isn't in `ordered` (different list section),
  /// fall back to Cmd-click semantics — matches Finder behaviour.
  func rangeSelect(to item: NavSelection, in ordered: [NavSelection]) {
    guard let anchor, let lo = ordered.firstIndex(of: anchor), let hi = ordered.firstIndex(of: item) else {
      toggle(item)
      return
    }
    let span = lo <= hi ? ordered[lo...hi] : ordered[hi...lo]
    // Union with existing so Shift-click after a prior Cmd-click extends
    // rather than blowing the prior selection away.
    selection.formUnion(span)
  }

  func clear() {
    selection.removeAll()
    anchor = nil
  }

  // MARK: - Convenience

  var isEmpty: Bool { selection.isEmpty }
  var count: Int { selection.count }
  func contains(_ item: NavSelection) -> Bool { selection.contains(item) }

  var bookmarkIds: [MWMMarkID] {
    selection.compactMap { if case let .bookmark(id) = $0 { return id } else { return nil } }
  }
  var trackIds: [MWMTrackID] {
    selection.compactMap { if case let .track(id) = $0 { return id } else { return nil } }
  }
  var bookmarkNSNumbers: [NSNumber] { bookmarkIds.map { NSNumber(value: $0) } }
  var trackNSNumbers: [NSNumber] { trackIds.map { NSNumber(value: $0) } }
}
