import AppKit
import Foundation

/// Chooses the engine's folders and exports them as `MWM_RESOURCES_DIR` and
/// `MWM_WRITABLE_DIR`, which `libs/platform/platform_mac.mm` reads once (both
/// must be set). The writable folder holds bookmarks, downloaded maps and
/// settings; the user can move it in Settings, which takes effect on relaunch.
enum DataDirectoryManager {
  private static let overrideKey = "OMDataDirectoryOverride"
  /// Fixed folder name, independent of the app's display name, so renaming the
  /// app never strands the user's data.
  private static let folderName = "com.maxparker72.mapo"
  private static var defaults: UserDefaults { .standard }

  /// Called from `MapoApp.init()` *before* any C++ code touches `Platform`.
  /// Variables already in the launch environment win, for debugging.
  static func configureEnvironment() {
    if getenv("MWM_RESOURCES_DIR") == nil {
      setenv("MWM_RESOURCES_DIR", resourcesDirectory().path + "/", 1)
    }
    if getenv("MWM_WRITABLE_DIR") == nil {
      let writable = usableOverride() ?? defaultDirectory()
      try? FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
      setenv("MWM_WRITABLE_DIR", writable.path + "/", 1)
    }
  }

  /// Debug builds read the repo's `data/` (found from this source file's path),
  /// so style and data edits show up without a Release build. Release builds use
  /// the copy bundled into Resources.
  private static func resourcesDirectory() -> URL {
    #if DEBUG
    let repo = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // App
      .deletingLastPathComponent()  // macos
      .deletingLastPathComponent()
    let data = repo.appendingPathComponent("data", isDirectory: true)
    if FileManager.default.fileExists(atPath: data.path) { return data }
    #endif
    return URL(fileURLWithPath: Bundle.main.resourcePath!, isDirectory: true)
  }

  private static func usableOverride() -> URL? {
    guard let path = defaults.string(forKey: overrideKey) else { return nil }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    guard exists, isDir.boolValue, FileManager.default.isWritableFile(atPath: path) else {
      NSLog("[mapo] Data folder override '\(path)' is missing or not writable; using the default.")
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  /// The directory the engine is actually using, as set by configureEnvironment().
  static func currentDirectory() -> URL {
    if let env = getenv("MWM_WRITABLE_DIR") { return URL(fileURLWithPath: String(cString: env), isDirectory: true) }
    return defaultDirectory()
  }

  static func defaultDirectory() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support.appendingPathComponent(folderName, isDirectory: true)
  }

  static var hasOverride: Bool { defaults.string(forKey: overrideKey) != nil }

  /// Persist a new override. If `copyFromCurrent` is true, copy every visible
  /// item from the current directory into `destination` first (overwriting on
  /// collision). Original files are left in place as an implicit backup; the
  /// user can delete them manually after verifying the new location works.
  /// Synchronous and potentially slow (MWMs can be GBs) — caller should
  /// invoke off the main thread.
  static func setOverride(to destination: URL, copyFromCurrent: Bool) throws {
    if copyFromCurrent {
      try copyDirectoryContents(from: currentDirectory(), to: destination)
    }
    defaults.set(destination.path, forKey: overrideKey)
  }

  static func clearOverride() { defaults.removeObject(forKey: overrideKey) }

  static func revealInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([currentDirectory()])
  }

  private static func copyDirectoryContents(from source: URL, to destination: URL) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: destination.path) {
      try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    }
    let items = try fm.contentsOfDirectory(atPath: source.path)
    for name in items {
      // Skip dotfiles except .Trash, which holds recently deleted bookmark categories
      // the engine restores from (see bookmark_helpers.cpp:322).
      if name.hasPrefix(".") && name != ".Trash" { continue }
      let src = source.appendingPathComponent(name)
      let dst = destination.appendingPathComponent(name)
      if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
      try fm.copyItem(at: src, to: dst)
    }
  }
}
