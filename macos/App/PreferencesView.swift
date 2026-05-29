import SwiftUI

/// Application preferences. Mirrors the iOS settings that apply to a desktop
/// planner (no real-time nav), grouped by tab.
struct PreferencesView: View {
  @StateObject private var model = PreferencesModel()

  var body: some View {
    TabView {
      GeneralTab(model: model)
        .tabItem { Label("General", systemImage: "gear") }

      MapTab(model: model)
        .tabItem { Label("Map", systemImage: "map") }

      RoutingTab(model: model)
        .tabItem { Label("Routing", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }

      DownloadsTab(model: model)
        .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

      StorageTab()
        .tabItem { Label("Storage", systemImage: "externaldrive") }

      AdvancedTab(model: model)
        .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
    }
    .frame(width: 520, height: 360)
  }
}

private struct GeneralTab: View {
  @ObservedObject var model: PreferencesModel

  var body: some View {
    Form {
      Picker("Units", selection: $model.units) {
        Text("Metric").tag(OMUnits.metric)
        Text("Imperial").tag(OMUnits.imperial)
      }
      Picker("Map Language", selection: $model.mapLanguage) {
        ForEach(model.availableMapLanguages) { lang in
          Text(lang.name).tag(lang.code)
        }
      }
      Toggle("Transliterate non-Latin labels", isOn: $model.transliteration)
      Toggle("Large map text", isOn: $model.largeFonts)
    }
    .padding(20)
  }
}

private struct MapTab: View {
  @ObservedObject var model: PreferencesModel

  var body: some View {
    Form {
      Picker("Style", selection: $model.mapStyle) {
        Text("Default Light").tag(OMMapStyleKind.defaultLight)
        Text("Default Dark").tag(OMMapStyleKind.defaultDark)
        Text("Vehicle Light").tag(OMMapStyleKind.vehicleLight)
        Text("Vehicle Dark").tag(OMMapStyleKind.vehicleDark)
        Text("Outdoors Light").tag(OMMapStyleKind.outdoorsLight)
        Text("Outdoors Dark").tag(OMMapStyleKind.outdoorsDark)
      }
      Toggle("3D buildings", isOn: $model.buildings3D)
      Picker("Bookmark labels", selection: $model.bookmarkPlacement) {
        Text("None").tag(OMBookmarkTextPlacement.none)
        Text("Right").tag(OMBookmarkTextPlacement.right)
        Text("Bottom").tag(OMBookmarkTextPlacement.bottom)
      }
    }
    .padding(20)
  }
}

private struct DownloadsTab: View {
  @ObservedObject var model: PreferencesModel

  var body: some View {
    Form {
      Toggle("Highlight downloaded regions on the map", isOn: $model.showDownloadedRegions)
    }
    .padding(20)
  }
}

private struct RoutingTab: View {
  @ObservedObject var model: PreferencesModel

  var body: some View {
    Form {
      Picker("Default mode", selection: $model.defaultRouter) {
        Text("Car").tag(0)
        Text("Walking").tag(1)
        Text("Cycling").tag(2)
        Text("Transit").tag(3)
        Text("Ruler").tag(4)
      }
      Section("Avoid (driving only)") {
        Toggle("Toll roads", isOn: $model.avoidTolls)
        Toggle("Motorways", isOn: $model.avoidMotorways)
        Toggle("Ferries", isOn: $model.avoidFerries)
        Toggle("Unpaved roads", isOn: $model.avoidDirty)
      }
      Text("These choices are the defaults for new routes. You can override them per route in the route builder.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(20)
  }
}

private struct StorageTab: View {
  @State private var currentPath: String = DataDirectoryManager.currentDirectory().path
  @State private var hasOverride: Bool = DataDirectoryManager.hasOverride
  @State private var isCopying = false
  @State private var error: String?
  @State private var showRestartAlert = false

  var body: some View {
    Form {
      Section("Data folder") {
        Text(currentPath)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
        HStack {
          Button("Reveal in Finder") { DataDirectoryManager.revealInFinder() }
          Spacer()
          if hasOverride {
            Button("Reset to Default") { resetToDefault() }
          }
          Button("Change Location…") { pickNewLocation() }
            .disabled(isCopying)
        }
        if isCopying {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Copying data to new location…").font(.caption)
          }
        }
        if let error {
          Text(error).font(.caption).foregroundStyle(.red)
        }
        Text("Bookmarks, downloaded map regions, and app settings live here. Changes take effect after you quit and reopen Organic Maps.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(20)
    .alert("Restart Required", isPresented: $showRestartAlert) {
      Button("OK") {}
    } message: {
      Text("Quit Organic Maps and reopen it to start using the new location.")
    }
  }

  private func pickNewLocation() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.message = "Choose a folder for Organic Maps data."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if url.path == currentPath {
      error = "That is already the current location."
      return
    }
    let alert = NSAlert()
    alert.messageText = "Move existing data?"
    alert.informativeText = "Copy bookmarks, downloaded maps, and settings from the current location into \"\(url.lastPathComponent)\"? Map data can be several gigabytes. Originals are left in place as a backup until you delete them manually."
    alert.addButton(withTitle: "Copy")
    alert.addButton(withTitle: "Don't Copy")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    if response == .alertThirdButtonReturn { return }
    let copy = (response == .alertFirstButtonReturn)
    isCopying = copy
    error = nil
    Task.detached(priority: .userInitiated) {
      do {
        try DataDirectoryManager.setOverride(to: url, copyFromCurrent: copy)
        await MainActor.run {
          currentPath = url.path
          hasOverride = true
          isCopying = false
          showRestartAlert = true
        }
      } catch {
        await MainActor.run {
          self.error = "Could not change location: \(error.localizedDescription)"
          isCopying = false
        }
      }
    }
  }

  private func resetToDefault() {
    DataDirectoryManager.clearOverride()
    currentPath = DataDirectoryManager.defaultDirectory().path
    hasOverride = false
    showRestartAlert = true
  }
}

private struct AdvancedTab: View {
  @ObservedObject var model: PreferencesModel

  var body: some View {
    Form {
      Toggle("Enable file logging", isOn: $model.fileLogging)
      Text("Restart the app for logging changes to take full effect.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(20)
  }
}
