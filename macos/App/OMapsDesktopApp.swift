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
    }

    Window("Download Maps", id: "maps-manager") {
      MapsManagerView()
    }
  }
}
