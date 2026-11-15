import SwiftUI

extension Notification.Name {
  /// Posted when item visibility changes from elsewhere (e.g. the filter window),
  /// so the navigator's eye icons stay in sync.
  static let omItemVisibilityChanged = Notification.Name("omItemVisibilityChanged")
  /// Posted whenever bookmark / track *display data* is mutated without an
  /// accompanying BookmarksObserver callback — color normalization on import,
  /// bulk Set Color, etc. `MWMBookmark` snapshots the bookmark colour at
  /// construction time, so a SwiftUI re-render alone isn't enough: the
  /// navigator has to re-call `sortedUserCategories()` to rebuild the
  /// snapshots. BookmarksNavigatorModel listens and calls `refresh()`.
  static let omBookmarkItemsChanged = Notification.Name("omBookmarkItemsChanged")
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

  /// Set by ContentView from the SwiftUI environment so bulk operations can
  /// register inverses for Cmd-Z. Weak because UndoManager outlives this
  /// model and we don't want a retain cycle.
  weak var undoManager: UndoManager?

  private var manager: BookmarksManager { BookmarksManager.shared() }

  private var visibilityObserver: NSObjectProtocol?
  private var itemsChangedObserver: NSObjectProtocol?

  override init() {
    super.init()
    // Cast to the protocol so this resolves to BookmarksObservable.addObserver(_:)
    // rather than NSObject's KVO addObserver(_:forKeyPath:options:context:).
    (manager as any BookmarksObservable).add(self)
    visibilityObserver = NotificationCenter.default.addObserver(
      forName: .omItemVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
      self?.objectWillChange.send()
    }
    itemsChangedObserver = NotificationCenter.default.addObserver(
      forName: .omBookmarkItemsChanged, object: nil, queue: .main) { [weak self] _ in
      self?.refresh()
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
    if let itemsChangedObserver { NotificationCenter.default.removeObserver(itemsChangedObserver) }
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
  func moveBookmark(_ id: MWMMarkID, to group: MWMMarkGroupID) {
    manager.move(bookmarks: [NSNumber(value: id)], tracks: [], toGroupId: group)
    refresh()
  }
  func moveTrack(_ id: MWMTrackID, to group: MWMMarkGroupID) {
    manager.move(bookmarks: [], tracks: [NSNumber(value: id)], toGroupId: group)
    refresh()
  }

  // MARK: - Bulk operations

  /// Delete the union of selected bookmarks and tracks in one edit session.
  func deleteItems(bookmarkIds: [NSNumber], trackIds: [NSNumber]) {
    if !bookmarkIds.isEmpty { OMBookmarksHelper.deleteBookmarks(bookmarkIds) }
    if !trackIds.isEmpty { OMBookmarksHelper.deleteTracks(trackIds) }
    refresh()
  }

  func moveItems(bookmarkIds: [NSNumber], trackIds: [NSNumber], to group: MWMMarkGroupID) {
    let bmIds = bookmarkIds.map { MWMMarkID($0.uint64Value) }
    let trIds = trackIds.map { MWMTrackID($0.uint64Value) }
    let prior = captureMoveAssignment(bookmarkIds: bmIds, trackIds: trIds)
    let forward = MoveAssignment(
      bookmarks: Dictionary(uniqueKeysWithValues: bmIds.map { ($0, group) }),
      tracks: Dictionary(uniqueKeysWithValues: trIds.map { ($0, group) }))
    applyMove(forward)
    registerMoveUndo(prior: prior, forward: forward, name: "Move Items")
  }

  func setColorForItems(bookmarkIds: [NSNumber], trackIds: [NSNumber], color: BookmarkColor) {
    let bmIds = bookmarkIds.map { MWMMarkID($0.uint64Value) }
    let trIds = trackIds.map { MWMTrackID($0.uint64Value) }
    let prior = captureColorAssignment(bookmarkIds: bmIds, trackIds: trIds)
    let forward = ColorAssignment(
      bookmarks: Dictionary(uniqueKeysWithValues: bmIds.map { ($0, color) }),
      tracks: Dictionary(uniqueKeysWithValues: trIds.map { ($0, color) }))
    applyColor(forward)
    registerColorUndo(prior: prior, forward: forward, name: "Set Color")
  }

  func setItemsVisible(bookmarkIds: [NSNumber], trackIds: [NSNumber], visible: Bool) {
    let bmIds = bookmarkIds.map { MWMMarkID($0.uint64Value) }
    let trIds = trackIds.map { MWMTrackID($0.uint64Value) }
    let prior = captureVisibilityAssignment(bookmarkIds: bmIds, trackIds: trIds)
    let forward = VisibilityAssignment(
      bookmarks: Dictionary(uniqueKeysWithValues: bmIds.map { ($0, visible) }),
      tracks: Dictionary(uniqueKeysWithValues: trIds.map { ($0, visible) }))
    applyVisibility(forward)
    registerVisibilityUndo(prior: prior, forward: forward,
                           name: visible ? "Show Items" : "Hide Items")
  }

  /// Add a tag to every selected item (union with each item's existing tags).
  /// `setTags` collapses duplicates and posts `.omTagsChanged`.
  func addTag(_ tag: String, bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) {
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let prior = captureTagAssignment(bookmarkIds: bookmarkIds, trackIds: trackIds)
    var forwardBm: [MWMMarkID: [String]] = [:]
    for id in bookmarkIds {
      var existing = prior.bookmarks[id] ?? []
      if !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        existing.append(trimmed)
      }
      forwardBm[id] = existing
    }
    var forwardTr: [MWMTrackID: [String]] = [:]
    for id in trackIds {
      var existing = prior.tracks[id] ?? []
      if !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        existing.append(trimmed)
      }
      forwardTr[id] = existing
    }
    let forward = TagAssignment(bookmarks: forwardBm, tracks: forwardTr)
    applyTags(forward)
    registerTagsUndo(prior: prior, forward: forward, name: "Add Tag")
  }

  func removeTag(_ tag: String, bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) {
    let prior = captureTagAssignment(bookmarkIds: bookmarkIds, trackIds: trackIds)
    var forwardBm: [MWMMarkID: [String]] = [:]
    for id in bookmarkIds {
      forwardBm[id] = (prior.bookmarks[id] ?? [])
        .filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }
    var forwardTr: [MWMTrackID: [String]] = [:]
    for id in trackIds {
      forwardTr[id] = (prior.tracks[id] ?? [])
        .filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }
    let forward = TagAssignment(bookmarks: forwardBm, tracks: forwardTr)
    applyTags(forward)
    registerTagsUndo(prior: prior, forward: forward, name: "Remove Tag")
  }

  // MARK: - Undoable building blocks

  private struct MoveAssignment {
    var bookmarks: [MWMMarkID: MWMMarkGroupID]
    var tracks: [MWMTrackID: MWMMarkGroupID]
  }
  private struct ColorAssignment {
    var bookmarks: [MWMMarkID: BookmarkColor]
    var tracks: [MWMTrackID: BookmarkColor]
  }
  private struct VisibilityAssignment {
    var bookmarks: [MWMMarkID: Bool]
    var tracks: [MWMTrackID: Bool]
  }
  private struct TagAssignment {
    var bookmarks: [MWMMarkID: [String]]
    var tracks: [MWMTrackID: [String]]
  }

  // Snapshots: captured before each forward operation so the undo handler
  // can restore the exact prior state per id.

  private func captureMoveAssignment(bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) -> MoveAssignment {
    var bm: [MWMMarkID: MWMMarkGroupID] = [:]
    for id in bookmarkIds { bm[id] = manager.category(forBookmarkId: id).categoryId }
    var tr: [MWMTrackID: MWMMarkGroupID] = [:]
    for id in trackIds { tr[id] = manager.category(forTrackId: id).categoryId }
    return MoveAssignment(bookmarks: bm, tracks: tr)
  }

  private func captureColorAssignment(bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) -> ColorAssignment {
    var bm: [MWMMarkID: BookmarkColor] = [:]
    for id in bookmarkIds { bm[id] = BookmarkColor.closest(to: manager.bookmark(withId: id).bookmarkColor) }
    var tr: [MWMTrackID: BookmarkColor] = [:]
    // Colors may not match the palette exactly; snap to the nearest palette
    // entry for the undo. Round-trip loss is the
    // cost of staying inside the BookmarkColor bulk-bridge.
    for id in trackIds {
      tr[id] = BookmarkColor.closest(to: manager.track(withId: id).trackColor)
    }
    return ColorAssignment(bookmarks: bm, tracks: tr)
  }

  private func captureVisibilityAssignment(bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) -> VisibilityAssignment {
    var bm: [MWMMarkID: Bool] = [:]
    for id in bookmarkIds { bm[id] = OMBookmarksHelper.isBookmarkVisible(id) }
    var tr: [MWMTrackID: Bool] = [:]
    for id in trackIds { tr[id] = OMBookmarksHelper.isTrackVisible(id) }
    return VisibilityAssignment(bookmarks: bm, tracks: tr)
  }

  private func captureTagAssignment(bookmarkIds: [MWMMarkID], trackIds: [MWMTrackID]) -> TagAssignment {
    var bm: [MWMMarkID: [String]] = [:]
    for id in bookmarkIds { bm[id] = OMBookmarksHelper.tags(forBookmark: id) }
    var tr: [MWMTrackID: [String]] = [:]
    for id in trackIds { tr[id] = OMBookmarksHelper.tags(forTrack: id) }
    return TagAssignment(bookmarks: bm, tracks: tr)
  }

  // Applies — bare engine writes. Used by both the forward action and the
  // undo handler, so each registers undo via the central register* methods
  // below, not from inside these.

  private func applyMove(_ assignment: MoveAssignment) {
    var bmByDest: [MWMMarkGroupID: [NSNumber]] = [:]
    for (id, dest) in assignment.bookmarks { bmByDest[dest, default: []].append(NSNumber(value: id)) }
    var trByDest: [MWMMarkGroupID: [NSNumber]] = [:]
    for (id, dest) in assignment.tracks { trByDest[dest, default: []].append(NSNumber(value: id)) }
    for (dest, ids) in bmByDest { OMBookmarksHelper.moveBookmarks(ids, to: dest) }
    for (dest, ids) in trByDest { OMBookmarksHelper.moveTracks(ids, to: dest) }
    refresh()
  }

  private func applyColor(_ assignment: ColorAssignment) {
    var bmByColor: [BookmarkColor: [NSNumber]] = [:]
    for (id, c) in assignment.bookmarks { bmByColor[c, default: []].append(NSNumber(value: id)) }
    var trByColor: [BookmarkColor: [NSNumber]] = [:]
    for (id, c) in assignment.tracks { trByColor[c, default: []].append(NSNumber(value: id)) }
    for (c, ids) in bmByColor { OMBookmarksHelper.setBookmarks(ids, color: c) }
    for (c, ids) in trByColor { OMBookmarksHelper.setTracks(ids, color: c) }
    OMBookmarksHelper.invalidateUserMarks()
    // MWMBookmark / MWMTrack snapshot color at init, so a bare
    // objectWillChange leaves the navigator rows showing the prior swatch.
    // Refresh rebuilds the snapshots from the post-edit engine state.
    refresh()
  }

  private func applyVisibility(_ assignment: VisibilityAssignment) {
    var bmByVis: [Bool: [NSNumber]] = [:]
    for (id, v) in assignment.bookmarks { bmByVis[v, default: []].append(NSNumber(value: id)) }
    var trByVis: [Bool: [NSNumber]] = [:]
    for (id, v) in assignment.tracks { trByVis[v, default: []].append(NSNumber(value: id)) }
    for (v, ids) in bmByVis { OMBookmarksHelper.setBookmarks(ids, visible: v) }
    for (v, ids) in trByVis { OMBookmarksHelper.setTracks(ids, visible: v) }
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  private func applyTags(_ assignment: TagAssignment) {
    for (id, tags) in assignment.bookmarks { OMBookmarksHelper.setTags(tags, forBookmark: id) }
    for (id, tags) in assignment.tracks { OMBookmarksHelper.setTags(tags, forTrack: id) }
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
  }

  // Undo registrations: each takes the prior (the inverse state) and the
  // forward (the redo state). When the undo handler fires it applies prior
  // and re-registers with swapped roles so Cmd-Shift-Z reproduces the
  // forward.

  private func registerMoveUndo(prior: MoveAssignment, forward: MoveAssignment, name: String) {
    undoManager?.setActionName(name)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyMove(prior)
      target.registerMoveUndo(prior: forward, forward: prior, name: name)
    }
  }

  private func registerColorUndo(prior: ColorAssignment, forward: ColorAssignment, name: String) {
    undoManager?.setActionName(name)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyColor(prior)
      target.registerColorUndo(prior: forward, forward: prior, name: name)
    }
  }

  private func registerVisibilityUndo(prior: VisibilityAssignment, forward: VisibilityAssignment, name: String) {
    undoManager?.setActionName(name)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyVisibility(prior)
      target.registerVisibilityUndo(prior: forward, forward: prior, name: name)
    }
  }

  private func registerTagsUndo(prior: TagAssignment, forward: TagAssignment, name: String) {
    undoManager?.setActionName(name)
    undoManager?.registerUndo(withTarget: self) { target in
      target.applyTags(prior)
      target.registerTagsUndo(prior: forward, forward: prior, name: name)
    }
  }

  // MARK: - BookmarksObserver

  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { refresh() }
  func onTrackDeleted(_ trackId: MWMTrackID) { refresh() }
}
