import AppKit
import Foundation
import UniformTypeIdentifiers

/// Orchestrates a batch import of bookmark files. Receives URLs (files or
/// folders), expands folders, shows a destination sheet (if 2+ files), then
/// loads each file through the engine. The engine doesn't tell us which
/// category a load produced (and even renames the file under the hood), so
/// the coordinator snapshots the current category set before the batch and
/// diffs after each file-load callback to find the new id. Once a new
/// category surfaces we apply post-import operations to it: tag every item,
/// add to a project, or move into a target list (with the auto-created
/// source category deleted afterwards).
///
/// Single-file imports skip the sheet so casual drops stay zero-friction.
///
/// Singleton because the sheet, the open-panel command, and the drop handler
/// all need to share the same in-flight batch state, and because the engine's
/// load callback is global — only one observer can sanely drive the
/// post-import bookkeeping.
@MainActor
final class ImportCoordinator: NSObject, ObservableObject, BookmarksObserver {
  static let shared = ImportCoordinator()

  struct Options: Equatable {
    var targetListId: MWMMarkGroupID?  // nil = keep as separate auto-named lists
    var tag: String?                   // nil = don't tag
    var projectId: MWMMarkGroupID?     // nil = don't add to project
  }

  /// State for the destination sheet. ContentView observes
  /// `pendingSheet` and renders the sheet when non-nil.
  struct SheetState: Identifiable {
    let id = UUID()
    let fileCount: Int
    let ignoredCount: Int
  }

  @Published var pendingSheet: SheetState?

  // Live-batch tracking.
  private var inProgress = false
  private var pendingConfirm: ((Options) -> Void)?
  private var options = Options()
  private var submittedCount = 0
  private var callbackCount = 0
  /// Set of category ids that existed *before* the batch started. New ids
  /// not in this set (and not in attributedCategoryIds) are the ones the
  /// engine just created for our newly-loaded files.
  private var baselineCategoryIds: Set<MWMMarkGroupID> = []
  /// New category ids we've already applied destination ops to.
  private var attributedCategoryIds: Set<MWMMarkGroupID> = []

  private var manager: BookmarksManager { BookmarksManager.shared() }

  // MARK: - Public entrypoints

  /// Modal NSOpenPanel that lets the user pick files and/or folders.
  func runOpenPanel() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.prompt = "Import"
    panel.message = "Choose bookmark files or a folder of files."
    if panel.runModal() == .OK {
      begin(panel.urls)
    }
  }

  /// Called from the drop handler or from the open panel. Folders are
  /// recursively expanded; non-supported file types are tallied for the
  /// sheet but otherwise ignored.
  func begin(_ urls: [URL]) {
    let (expanded, ignored) = Self.expand(urls)
    guard !expanded.isEmpty else { return }

    // Skip the sheet for single-file imports — that's the casual "drop one
    // GPX on the map" path and it shouldn't suddenly demand a decision.
    if expanded.count == 1 {
      load(expanded, with: Options())
      return
    }

    pendingSheet = SheetState(fileCount: expanded.count, ignoredCount: ignored)
    pendingConfirm = { [weak self] opts in
      self?.pendingSheet = nil
      self?.pendingConfirm = nil
      self?.load(expanded, with: opts)
    }
  }

  // Called by the sheet view.
  func confirm(_ options: Options) {
    pendingConfirm?(options)
  }

  func cancelSheet() {
    pendingSheet = nil
    pendingConfirm = nil
  }

  // MARK: - Batch execution

  private func load(_ urls: [URL], with options: Options) {
    if inProgress {
      // Rare race: another batch already running. Stack these on top.
      submittedCount += urls.count
    } else {
      self.options = options
      baselineCategoryIds = Set(manager.sortedUserCategories().map(\.categoryId))
      attributedCategoryIds = []
      submittedCount = urls.count
      callbackCount = 0
      inProgress = true
      (manager as any BookmarksObservable).add(self)
    }
    for url in urls { manager.loadBookmarkFile(url) }
  }

  // MARK: - BookmarksObserver

  func onBookmarksFileLoadSuccess() { handleCallback() }
  func onBookmarksFileLoadError() { handleCallback() }

  private func handleCallback() {
    guard inProgress else { return }
    callbackCount += 1
    let isLast = callbackCount >= submittedCount
    // The engine fires our success callback *before* CreateCategories runs
    // (both are dispatched to the Gui thread, but the file-success notice is
    // enqueued first). Defer one runloop so CreateCategories has executed and
    // the new category is actually in BookmarkManager::m_categories — without
    // this, GetCategoryByFileName / GetGroup would see the id as invalid.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.drainNewCategories()
      if isLast { self.finalizeBatch() }
    }
  }

  /// Compare the engine's current category set against our pre-batch baseline
  /// to find categories newly created by this batch. Apply destination ops to
  /// each one once; track in `attributedCategoryIds` so we don't double-apply
  /// on later callbacks. This is robust to:
  ///  - the engine generating its own file paths (we can't look up by drop URL)
  ///  - out-of-order or coalesced GUI callbacks
  ///  - the destination ops themselves deleting the source category
  private func drainNewCategories() {
    let current = Set(manager.sortedUserCategories().map(\.categoryId))
    let newIds = current
      .subtracting(baselineCategoryIds)
      .subtracting(attributedCategoryIds)
    for groupId in newIds {
      applyDestination(to: groupId)
      attributedCategoryIds.insert(groupId)
    }
  }

  private func applyDestination(to groupId: MWMMarkGroupID) {
    let bms = OMBookmarksHelper.bookmarkIds(inCategory: groupId)
    let trs = OMBookmarksHelper.trackIds(inCategory: groupId)

    if let tag = options.tag, !tag.isEmpty {
      for n in bms {
        let id = n.uint64Value
        var existing = OMBookmarksHelper.tags(forBookmark: id)
        if !existing.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
          existing.append(tag)
          OMBookmarksHelper.setTags(existing, forBookmark: id)
        }
      }
      for n in trs {
        let id = n.uint64Value
        var existing = OMBookmarksHelper.tags(forTrack: id)
        if !existing.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
          existing.append(tag)
          OMBookmarksHelper.setTags(existing, forTrack: id)
        }
      }
    }

    if let projectId = options.projectId, projectId != 0 {
      for n in bms { OMProjectsHelper.addBookmark(n.uint64Value, toProject: projectId) }
      for n in trs { OMProjectsHelper.addTrack(n.uint64Value, toProject: projectId) }
    }

    if let target = options.targetListId, target != groupId, target != 0 {
      OMBookmarksHelper.moveBookmarks(bms, to: target)
      OMBookmarksHelper.moveTracks(trs, to: target)
      // The file's auto-created category is now empty; remove it so the
      // navigator doesn't end up cluttered with one empty list per file.
      manager.deleteCategory(groupId)
    }
  }

  private func finalizeBatch() {
    inProgress = false
    options = Options()
    submittedCount = 0
    callbackCount = 0
    baselineCategoryIds = []
    attributedCategoryIds = []
    (manager as any BookmarksObservable).remove(self)
    NotificationCenter.default.post(name: .omTagsChanged, object: nil)
    NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
  }

  // MARK: - Folder expansion

  private static let allowedExtensions: Set<String> = ["gpx", "kml", "kmz", "geojson", "json"]

  /// Recursively walk any directories in `urls`, returning all files with
  /// supported extensions plus a count of files that were skipped because
  /// their extension didn't match. Hidden files are skipped.
  static func expand(_ urls: [URL]) -> (expanded: [URL], ignored: Int) {
    var result: [URL] = []
    var ignored = 0
    let fm = FileManager.default
    for url in urls {
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
      if isDir.boolValue {
        guard let enumerator = fm.enumerator(
          at: url,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        ) else { continue }
        for case let fileURL as URL in enumerator {
          let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
          guard values?.isRegularFile == true else { continue }
          if allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
            result.append(fileURL)
          } else {
            ignored += 1
          }
        }
      } else {
        if allowedExtensions.contains(url.pathExtension.lowercased()) {
          result.append(url)
        } else {
          ignored += 1
        }
      }
    }
    return (result, ignored)
  }
}
