import Foundation

enum PropertyKind { case text, choice, number }

enum FilterProperty: String, CaseIterable, Identifiable {
  case name = "Name"
  case type = "Type"
  case description = "Description"
  case color = "Color"
  case list = "List"
  case tag = "Tag"
  case region = "Region"
  case distance = "Distance (m)"
  case length = "Length (m)"

  var id: String { rawValue }
  var isNumeric: Bool { kind == .number }

  var kind: PropertyKind {
    switch self {
    case .name, .description: return .text
    case .type, .color, .list, .tag, .region: return .choice
    case .distance, .length: return .number
    }
  }

  // Some properties only make sense for one item type.
  var appliesToBookmarks: Bool { self != .length }
  var appliesToTracks: Bool {
    switch self {
    case .name, .description, .list, .length, .tag, .region: return true
    default: return false
    }
  }
}

enum StringOp: String, CaseIterable, Identifiable, Codable {
  case isExactly = "is"
  case isNot = "is not"
  case contains = "contains"
  case notContains = "does not contain"
  case startsWith = "starts with"
  case endsWith = "ends with"
  var id: String { rawValue }
}

enum NumberOp: String, CaseIterable, Identifiable, Codable {
  case eq = "="
  case ne = "≠"
  case gt = ">"
  case lt = "<"
  case ge = "≥"
  case le = "≤"
  var id: String { rawValue }
}

struct FilterCondition: Identifiable, Codable, Equatable {
  // `id` is in-memory only — fresh UUID on decode so saved filters don't
  // collide if duplicated in the UI.
  let id = UUID()
  var property: FilterProperty = .name
  var stringOp: StringOp = .contains
  var numberOp: NumberOp = .gt
  var value: String = ""

  enum CodingKeys: String, CodingKey {
    case property, stringOp, numberOp, value
  }
}

extension FilterProperty: Codable {}

/// Named, persisted FilterModel state. Restoring a SavedFilter into a
/// FilterModel and calling apply() reproduces the saved view exactly.
struct SavedFilter: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var matchAll: Bool
  var conditions: [FilterCondition]

  init(id: UUID = UUID(), name: String, matchAll: Bool, conditions: [FilterCondition]) {
    self.id = id
    self.name = name
    self.matchAll = matchAll
    self.conditions = conditions
  }
}

/// A visual filter over bookmarks (waypoints): a set of property conditions
/// chained by AND/OR. Applying hides non-matching bookmarks on the map.
/// (Tracks can't be hidden individually by the engine, so they're unaffected.)
final class FilterModel: ObservableObject {
  @Published var matchAll = true  // true = AND, false = OR
  @Published var conditions: [FilterCondition] = [FilterCondition()]

  func addCondition() { conditions.append(FilterCondition()) }
  func removeCondition(_ condition: FilterCondition) { conditions.removeAll { $0.id == condition.id } }

  /// Capture the current state into a named `SavedFilter` for persistence.
  func snapshot(name: String, id: UUID = UUID()) -> SavedFilter {
    SavedFilter(id: id, name: name, matchAll: matchAll, conditions: conditions)
  }

  /// Replace the current state with a saved filter, without applying.
  func restore(_ saved: SavedFilter) {
    matchAll = saved.matchAll
    conditions = saved.conditions
  }

  /// One-shot apply: build a transient FilterModel from a saved filter and
  /// run apply(). Used by NavigatorView and the Filter menu when the user
  /// doesn't need to open the builder.
  static func applyOneShot(_ saved: SavedFilter) {
    let m = FilterModel()
    m.restore(saved)
    m.apply()
  }

  /// Evaluate every bookmark/track against the current condition set and
  /// return the matching ids — used by the "Select Matching" button so the
  /// user can run bulk operations on the filter's result through the
  /// navigator's selection model.
  func matchingIds() -> (bookmarks: [MWMMarkID], tracks: [MWMTrackID]) {
    let lists = BookmarksManager.shared().sortedUserCategories()
    var bms: [MWMMarkID] = []
    var trs: [MWMTrackID] = []
    for list in lists {
      for bm in list.bookmarks where evaluateBookmark(bm, listName: list.title) {
        bms.append(bm.bookmarkId)
      }
      for track in list.tracks where evaluateTrack(track, listName: list.title) {
        trs.append(track.trackId)
      }
    }
    return (bms, trs)
  }

  /// Hide items that don't match; show those that do. An item is evaluated only
  /// against the conditions that apply to its type; an item with no applicable
  /// condition is hidden (the filter is clearly targeting the other type).
  func apply() {
    let lists = BookmarksManager.shared().sortedUserCategories()
    var bmShow: [NSNumber] = [], bmHide: [NSNumber] = []
    var trkShow: [NSNumber] = [], trkHide: [NSNumber] = []
    for list in lists {
      for bookmark in list.bookmarks {
        let id = NSNumber(value: bookmark.bookmarkId)
        if evaluateBookmark(bookmark, listName: list.title) { bmShow.append(id) } else { bmHide.append(id) }
      }
      for track in list.tracks {
        let id = NSNumber(value: track.trackId)
        if evaluateTrack(track, listName: list.title) { trkShow.append(id) } else { trkHide.append(id) }
      }
    }
    OMBookmarksHelper.setBookmarks(bmShow, visible: true)
    OMBookmarksHelper.setBookmarks(bmHide, visible: false)
    OMBookmarksHelper.setTracks(trkShow, visible: true)
    OMBookmarksHelper.setTracks(trkHide, visible: false)
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  // MARK: - Evaluation

  private func evaluateBookmark(_ bookmark: Bookmark, listName: String) -> Bool {
    let applicable = conditions.filter { $0.property.appliesToBookmarks }
    guard !applicable.isEmpty else { return false }
    let results = applicable.map { matches($0, bookmark, listName) }
    return matchAll ? results.allSatisfy { $0 } : results.contains(true)
  }

  private func evaluateTrack(_ track: Track, listName: String) -> Bool {
    let applicable = conditions.filter { $0.property.appliesToTracks }
    guard !applicable.isEmpty else { return false }
    let results = applicable.map { matchesTrack($0, track, listName) }
    return matchAll ? results.allSatisfy { $0 } : results.contains(true)
  }

  private func matchesTrack(_ condition: FilterCondition, _ track: Track, _ listName: String) -> Bool {
    if condition.property == .length {
      guard let rhs = Double(condition.value) else { return false }
      let lhs = Double(track.trackLengthMeters)
      switch condition.numberOp {
      case .eq: return lhs == rhs
      case .ne: return lhs != rhs
      case .gt: return lhs > rhs
      case .lt: return lhs < rhs
      case .ge: return lhs >= rhs
      case .le: return lhs <= rhs
      }
    }
    if condition.property == .tag {
      return Self.evaluateTagMembership(OMBookmarksHelper.tags(forTrack: track.trackId), condition)
    }
    if condition.property == .region {
      return Self.evaluateTagMembership(OMBookmarksHelper.regions(forTrack: track.trackId), condition)
    }
    let lhs: String
    switch condition.property {
    case .name: lhs = track.trackName
    case .description: lhs = EntityEditor.trackDescription(track.trackId)
    case .list: lhs = listName
    default: return false
    }
    return compareString(lhs, condition)
  }

  // For .tag (a set-valued property), reuse StringOp's binary axes: .isExactly
  // = "has", .isNot = "does not have". The FilterView relabels them when the
  // property is .tag so the UI reads naturally.
  static func evaluateTagMembership(_ tags: [String], _ condition: FilterCondition) -> Bool {
    let has = tags.contains { $0.caseInsensitiveCompare(condition.value) == .orderedSame }
    switch condition.stringOp {
    case .isExactly: return has
    case .isNot: return !has
    default: return false
    }
  }

  private func compareString(_ lhs: String, _ condition: FilterCondition) -> Bool {
    let rhs = condition.value
    switch condition.stringOp {
    case .isExactly: return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    case .isNot: return lhs.caseInsensitiveCompare(rhs) != .orderedSame
    case .contains: return lhs.localizedCaseInsensitiveContains(rhs)
    case .notContains: return !lhs.localizedCaseInsensitiveContains(rhs)
    case .startsWith: return lhs.lowercased().hasPrefix(rhs.lowercased())
    case .endsWith: return lhs.lowercased().hasSuffix(rhs.lowercased())
    }
  }

  private func matches(_ condition: FilterCondition, _ bookmark: Bookmark, _ listName: String) -> Bool {
    if condition.property == .tag {
      return Self.evaluateTagMembership(OMBookmarksHelper.tags(forBookmark: bookmark.bookmarkId), condition)
    }
    if condition.property == .region {
      return Self.evaluateTagMembership(OMBookmarksHelper.regions(forBookmark: bookmark.bookmarkId), condition)
    }
    if condition.property.isNumeric {
      guard let rhs = Double(condition.value) else { return false }
      let lhs = numericValue(condition.property, bookmark)
      guard lhs >= 0 else { return false }  // unknown (e.g. no location)
      switch condition.numberOp {
      case .eq: return lhs == rhs
      case .ne: return lhs != rhs
      case .gt: return lhs > rhs
      case .lt: return lhs < rhs
      case .ge: return lhs >= rhs
      case .le: return lhs <= rhs
      }
    } else {
      return compareString(stringValue(condition.property, bookmark, listName), condition)
    }
  }

  private func stringValue(_ property: FilterProperty, _ bookmark: Bookmark, _ listName: String) -> String {
    switch property {
    case .name: return bookmark.bookmarkName
    case .type: return bookmark.bookmarkType ?? ""
    case .description: return EntityEditor.bookmarkDescription(bookmark.bookmarkId)
    case .color: return BookmarkColor.closest(to: bookmark.bookmarkColor).displayName
    case .list: return listName
    case .tag, .region, .distance, .length: return ""  // handled in matches() directly
    }
  }

  private func numericValue(_ property: FilterProperty, _ bookmark: Bookmark) -> Double {
    switch property {
    case .distance:
      return OMBookmarksHelper.metersFromCurrentPosition(toLat: bookmark.locationCoordinate.latitude,
                                                         lon: bookmark.locationCoordinate.longitude)
    default: return -1
    }
  }
}
