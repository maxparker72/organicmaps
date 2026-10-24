import SwiftUI

extension Notification.Name {
  /// Posted by the "Find in Library" command. ContentView listens, opens the
  /// navigator if hidden, and focuses its search field.
  static let omFindInLibrary = Notification.Name("omFindInLibrary")
  /// Posted by Cmd-Y and the navigator's Space key. ContentView toggles the
  /// Quick Look sheet, resolving the target item from the selection.
  static let omToggleQuickLook = Notification.Name("omToggleQuickLook")
  /// Posted by FilterView's "Select Matching" button with userInfo
  /// {"bookmarks": [UInt64], "tracks": [UInt64]}. ContentView replaces the
  /// navigator selection with those ids so the user can run bulk ops
  /// against the filter result.
  static let omSelectMatchingFilter = Notification.Name("omSelectMatchingFilter")
}

@main
struct OMapsDesktopApp: App {
  @Environment(\.openWindow) private var openWindow

  init() {
    // Set MWM_WRITABLE_DIR from user override before anything constructs the
    // C++ Platform singleton (which reads it once and caches the path).
    DataDirectoryManager.applyOverrideIfPresent()
  }

  var body: some Scene {
    // A single main window: the map engine exists once per process (D-08).
    Window("BDSM", id: "main") {
      ContentView()
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Download Maps…") {
          openWindow(id: "maps-manager")
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        Button("Import Bookmarks…") {
          BookmarkFiles.runImportPanel()
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        Button("Normalize Bookmarks & Tracks") {
          OMBookmarksHelper.normalizeAllItems()
        }
        Button("Back Up Bookmarks…") {
          BookmarkFiles.runBackupPanel()
        }
      }
      CommandMenu("Filter") {
        Button("Filter Bookmarks…") { openWindow(id: "filter-builder") }
          .keyboardShortcut("f", modifiers: [.command, .shift])
        SavedFiltersMenu()
        Button("Clear Filter") {
          BookmarksManager.shared().setUserCategoriesVisible(true)
          OMBookmarksHelper.showAllItems()
          NotificationCenter.default.post(name: .omItemVisibilityChanged, object: nil)
          SavedFiltersStore.shared.setActive(nil)
        }
        Divider()
        Button("Find in Library") {
          NotificationCenter.default.post(name: .omFindInLibrary, object: nil)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
      }
      // Map controls live in the menu bar / shortcuts to keep the map clean.
      CommandGroup(after: .sidebar) {
        Button("Zoom In") { OMMapControls.zoomIn() }
          .keyboardShortcut("+", modifiers: .command)
        Button("Zoom Out") { OMMapControls.zoomOut() }
          .keyboardShortcut("-", modifiers: .command)
        Button("My Location") { OMLocationController.followMyPosition() }
          .keyboardShortcut("l", modifiers: .command)
        Button("Orient North") { OMMapControls.rotateToNorth() }
        Divider()
        Button("Quick Look") {
          NotificationCenter.default.post(name: .omToggleQuickLook, object: nil)
        }
        .keyboardShortcut("y", modifiers: .command)
      }
    }

    Window("Download Maps", id: "maps-manager") {
      MapsManagerView()
    }

    Window("Filter Bookmarks", id: "filter-builder") {
      FilterView()
    }

    Settings {
      PreferencesView()
    }
  }
}

/// Renders the saved-filter list inside the Filter menu. Pulled out so it can
/// observe `SavedFiltersStore.shared` and refresh as filters are added or
/// renamed without rebuilding the menu structure manually.
private struct SavedFiltersMenu: View {
  @ObservedObject private var saved = SavedFiltersStore.shared

  var body: some View {
    Menu("Apply Saved Filter") {
      if saved.filters.isEmpty {
        Text("No saved filters yet").foregroundStyle(.secondary)
      } else {
        ForEach(saved.filters) { filter in
          Button(filter.name) {
            FilterModel.applyOneShot(filter)
            saved.setActive(filter.id)
          }
        }
      }
    }
    .disabled(saved.filters.isEmpty)
  }
}
