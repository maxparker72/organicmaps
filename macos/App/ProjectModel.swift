import Foundation

/// A "project" — an arbitrary cross-list grouping of bookmarks and tracks.
/// Backed by a `kml::CategoryData` whose `m_properties["kind"] == "project"`;
/// membership is held as a `project:<projectId>` tag on each member entity.
struct Project: Identifiable, Equatable {
  let categoryId: MWMMarkGroupID
  let projectId: String
  var name: String
  var startDate: Date?
  var endDate: Date?
  var itinerary: [ItineraryEntry]

  var id: MWMMarkGroupID { categoryId }
}

struct ItineraryEntry: Identifiable, Codable, Equatable {
  enum Kind: String, Codable { case bookmark, track }

  var id = UUID()
  var kind: Kind
  var ref: UInt64
  var note: String?

  enum CodingKeys: String, CodingKey { case kind, ref, note }
}

final class ProjectModel: NSObject, ObservableObject, BookmarksObserver {
  @Published private(set) var projects: [Project] = []
  @Published private(set) var isolatedProjectId: MWMMarkGroupID?

  /// Snapshot of per-entity visibility captured when isolation mode is entered.
  /// Restored verbatim on unisolate. Items created during isolation aren't in
  /// the snapshot; those default to visible on restore.
  private struct VisibilitySnapshot {
    let bookmarks: [MWMMarkID: Bool]
    let tracks: [MWMTrackID: Bool]
    let categories: [MWMMarkGroupID: Bool]
  }
  private var visibilitySnapshot: VisibilitySnapshot?

  private var manager: BookmarksManager { BookmarksManager.shared() }

  override init() {
    super.init()
    (manager as any BookmarksObservable).add(self)
    if manager.areBookmarksLoaded() { refresh() }
  }

  deinit {
    (BookmarksManager.shared() as any BookmarksObservable).remove(self)
  }

  func refresh() {
    let ids = OMProjectsHelper.projectCategoryIds()
    projects = ids.compactMap { Self.loadProject(categoryId: $0.uint64Value) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  // MARK: - CRUD

  @discardableResult
  func createProject(name: String) -> MWMMarkGroupID {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    let id = OMProjectsHelper.createProject(withName: trimmed)
    refresh()
    return id
  }

  func delete(_ project: Project) {
    if isolatedProjectId == project.categoryId { unisolate() }
    OMProjectsHelper.deleteProject(project.categoryId)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    refresh()
  }

  func rename(_ project: Project, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    OMProjectsHelper.renameProject(project.categoryId, to: trimmed)
    refresh()
  }

  func setStartDate(_ date: Date?, project: Project) {
    OMProjectsHelper.setProperty(
      date.map(Self.dateFormatter.string(from:)),
      forKey: OMProjectStartDateKey, project: project.categoryId)
    refresh()
  }

  func setEndDate(_ date: Date?, project: Project) {
    OMProjectsHelper.setProperty(
      date.map(Self.dateFormatter.string(from:)),
      forKey: OMProjectEndDateKey, project: project.categoryId)
    refresh()
  }

  // MARK: - Membership

  func addBookmark(_ bookmarkId: MWMMarkID, to project: Project) {
    OMProjectsHelper.addBookmark(bookmarkId, toProject: project.categoryId)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    reapplyIsolationIfAffected(project)
    objectWillChange.send()
  }
  func removeBookmark(_ bookmarkId: MWMMarkID, from project: Project) {
    OMProjectsHelper.removeBookmark(bookmarkId, fromProject: project.categoryId)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    reapplyIsolationIfAffected(project)
    objectWillChange.send()
  }
  func addTrack(_ trackId: MWMTrackID, to project: Project) {
    OMProjectsHelper.addTrack(trackId, toProject: project.categoryId)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    reapplyIsolationIfAffected(project)
    objectWillChange.send()
  }
  func removeTrack(_ trackId: MWMTrackID, from project: Project) {
    OMProjectsHelper.removeTrack(trackId, fromProject: project.categoryId)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    reapplyIsolationIfAffected(project)
    objectWillChange.send()
  }

  // MARK: - Isolation

  func isIsolated(_ project: Project) -> Bool { isolatedProjectId == project.categoryId }

  func toggleIsolation(_ project: Project) {
    if isolatedProjectId == project.categoryId { unisolate() } else { isolate(project) }
  }

  func isolate(_ project: Project) {
    // Snapshot only on entry — switching between isolated projects preserves
    // the original pre-isolation state.
    if visibilitySnapshot == nil { visibilitySnapshot = captureCurrentVisibility() }
    applyIsolation(project: project)
    isolatedProjectId = project.categoryId
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  func unisolate() {
    guard let snap = visibilitySnapshot else { isolatedProjectId = nil; return }
    restore(snapshot: snap)
    visibilitySnapshot = nil
    isolatedProjectId = nil
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  private func reapplyIsolationIfAffected(_ project: Project) {
    guard isolatedProjectId == project.categoryId else { return }
    applyIsolation(project: project)
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  private func captureCurrentVisibility() -> VisibilitySnapshot {
    var bms: [MWMMarkID: Bool] = [:]
    var trs: [MWMTrackID: Bool] = [:]
    var cats: [MWMMarkGroupID: Bool] = [:]
    for list in manager.sortedUserCategories() {
      cats[list.categoryId] = list.isVisible
      for bm in list.bookmarks { bms[bm.bookmarkId] = OMBookmarksHelper.isBookmarkVisible(bm.bookmarkId) }
      for tr in list.tracks { trs[tr.trackId] = OMBookmarksHelper.isTrackVisible(tr.trackId) }
    }
    return VisibilitySnapshot(bookmarks: bms, tracks: trs, categories: cats)
  }

  private func applyIsolation(project: Project) {
    let memberBookmarks = Set(bookmarkIds(in: project))
    let memberTracks = Set(trackIds(in: project))
    var memberCategories: Set<MWMMarkGroupID> = []
    var bmsShow: [NSNumber] = [], bmsHide: [NSNumber] = []
    var trsShow: [NSNumber] = [], trsHide: [NSNumber] = []
    for list in manager.sortedUserCategories() {
      var hasMember = false
      for bm in list.bookmarks {
        let n = NSNumber(value: bm.bookmarkId)
        if memberBookmarks.contains(bm.bookmarkId) { bmsShow.append(n); hasMember = true }
        else { bmsHide.append(n) }
      }
      for tr in list.tracks {
        let n = NSNumber(value: tr.trackId)
        if memberTracks.contains(tr.trackId) { trsShow.append(n); hasMember = true }
        else { trsHide.append(n) }
      }
      if hasMember { memberCategories.insert(list.categoryId) }
    }
    // Categories containing members must be visible so individual items render;
    // hide the rest so the navigator's eyes mirror the isolation state.
    for list in manager.sortedUserCategories() {
      manager.setCategory(list.categoryId, isVisible: memberCategories.contains(list.categoryId))
    }
    OMBookmarksHelper.setBookmarks(bmsShow, visible: true)
    OMBookmarksHelper.setBookmarks(bmsHide, visible: false)
    OMBookmarksHelper.setTracks(trsShow, visible: true)
    OMBookmarksHelper.setTracks(trsHide, visible: false)
  }

  private func restore(snapshot: VisibilitySnapshot) {
    // Default to fully-visible so items created during isolation aren't left
    // hidden on resume, then re-apply the snapshot's hidden entries.
    OMBookmarksHelper.showAllItems()
    manager.setUserCategoriesVisible(true)
    var bmsHide: [NSNumber] = []
    for (id, vis) in snapshot.bookmarks where !vis { bmsHide.append(NSNumber(value: id)) }
    var trsHide: [NSNumber] = []
    for (id, vis) in snapshot.tracks where !vis { trsHide.append(NSNumber(value: id)) }
    OMBookmarksHelper.setBookmarks(bmsHide, visible: false)
    OMBookmarksHelper.setTracks(trsHide, visible: false)
    for (catId, vis) in snapshot.categories where !vis {
      manager.setCategory(catId, isVisible: false)
    }
  }

  func bookmarkIds(in project: Project) -> [MWMMarkID] {
    OMProjectsHelper.bookmarkIds(inProject: project.categoryId).map { MWMMarkID($0.uint64Value) }
  }
  func trackIds(in project: Project) -> [MWMTrackID] {
    OMProjectsHelper.trackIds(inProject: project.categoryId).map { MWMTrackID($0.uint64Value) }
  }

  func memberCount(_ project: Project) -> Int {
    bookmarkIds(in: project).count + trackIds(in: project).count
  }

  // MARK: - Itinerary

  func setItinerary(_ entries: [ItineraryEntry], project: Project) {
    let value: String?
    if entries.isEmpty {
      value = nil
    } else if let data = try? JSONEncoder().encode(entries),
              let str = String(data: data, encoding: .utf8) {
      value = str
    } else {
      value = nil
    }
    OMProjectsHelper.setProperty(value, forKey: OMProjectItineraryKey, project: project.categoryId)
    refresh()
  }

  // MARK: - Loading

  private static func loadProject(categoryId: MWMMarkGroupID) -> Project? {
    guard let projectId = OMProjectsHelper.projectId(forCategoryId: categoryId),
          let name = OMProjectsHelper.name(forProject: categoryId) else { return nil }
    let start = OMProjectsHelper.property(forKey: OMProjectStartDateKey, project: categoryId)
      .flatMap(dateFormatter.date(from:))
    let end = OMProjectsHelper.property(forKey: OMProjectEndDateKey, project: categoryId)
      .flatMap(dateFormatter.date(from:))
    let itinerary = OMProjectsHelper.property(forKey: OMProjectItineraryKey, project: categoryId)
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONDecoder().decode([ItineraryEntry].self, from: $0) } ?? []
    return Project(categoryId: categoryId, projectId: projectId, name: name,
                   startDate: start, endDate: end, itinerary: itinerary)
  }

  private static let dateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return f
  }()

  // MARK: - BookmarksObserver

  func onBookmarksLoadFinished() { refresh() }
  func onBookmarksFileLoadSuccess() { refresh() }
  func onBookmarksCategoryDeleted(_ groupId: MWMMarkGroupID) { refresh() }
  func onBookmarkDeleted(_ bookmarkId: MWMMarkID) { objectWillChange.send() }
  func onTrackDeleted(_ trackId: MWMTrackID) { objectWillChange.send() }
}
