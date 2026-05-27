import SwiftUI

struct ContentView: View {
  // Placeholder sidebar sections; real bookmark/track organization comes in Phase 2.
  private enum SidebarItem: String, CaseIterable, Identifiable {
    case map = "Map"
    case bookmarks = "Bookmarks"
    case tracks = "Tracks"
    var id: String { rawValue }
  }

  @State private var selection: SidebarItem? = .map

  var body: some View {
    NavigationSplitView {
      List(SidebarItem.allCases, selection: $selection) { item in
        Text(item.rawValue).tag(item)
      }
      .navigationTitle("Organic Maps")
      .frame(minWidth: 200)
    } detail: {
      MapView()
        .ignoresSafeArea()
    }
  }
}
