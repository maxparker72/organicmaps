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
