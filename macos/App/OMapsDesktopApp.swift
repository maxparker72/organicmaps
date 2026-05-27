import SwiftUI

@main
struct OMapsDesktopApp: App {
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    WindowGroup {
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
      }
    }

    Window("Download Maps", id: "maps-manager") {
      MapsManagerView()
    }
  }
}
