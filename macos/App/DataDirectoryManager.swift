import AppKit
import Foundation

/// User-chosen override for the engine's writable directory (where bookmarks,
/// downloaded MWMs, and settings live). Reads from NSUserDefaults and exports
/// it to the C++ `Platform` via the `MWM_WRITABLE_DIR` env var at app launch.
/// Changes only take effect after the app is relaunched (the Platform reads
/// the env var once in its constructor — see libs/platform/platform_mac.mm).
enum DataDirectoryManager {
  private static let overrideKey = "OMDataDirectoryOverride"
  private static var defaults: UserDefaults { .standard }

  /// Called from `OMapsDesktopApp.init()` *before* any C++ code touches the
  /// `Platform` singleton. If the user has chosen a custom data folder, set
  /// the env vars `platform_mac.mm` looks at; otherwise leave the launch
  /// environment alone so the existing fallbacks (Xcode scheme env, then
  /// `~/Library/Application Support/OMapsData/`) apply.
  static func applyOverrideIfPresent() {
    guard let path = defaults.string(forKey: overrideKey) else { return }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    guard exists, isDir.boolValue, FileManager.default.isWritableFile(atPath: path) else {
      NSLog("[OMaps] Data folder override '\(path)' is missing or not writable; falling back.")
      return
    }
    setenv("MWM_WRITABLE_DIR", path, 1)
    // platform_mac.mm only takes the env-var branch when both vars are set
    // together. Dev builds get MWM_RESOURCES_DIR from the Xcode scheme; a
    // shipped binary does not, so fall back to the app bundle Resources.
    if getenv("MWM_RESOURCES_DIR") == nil, let resources = Bundle.main.resourcePath {
      setenv("MWM_RESOURCES_DIR", resources + "/", 1)
    }
  }

  /// The directory the engine is *actually* using right now. Override wins;
  /// otherwise reflect whatever the launch environment resolved to.
  static func currentDirectory() -> URL {
    if let path = defaults.string(forKey: overrideKey) { return URL(fileURLWithPath: path) }
    if let env = ProcessInfo.processInfo.environment["MWM_WRITABLE_DIR"] {
      return URL(fileURLWithPath: env)
    }
    return defaultDirectory()
  }

  /// Mirrors the shipped-app fallback in `platform_mac.mm` lines 103–114.
  static func defaultDirectory() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support.appendingPathComponent("OMapsData", isDirectory: true)
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
