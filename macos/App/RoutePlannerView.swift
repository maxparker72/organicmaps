import SwiftUI

/// Floating route planner card. Shows the points being routed between, the
/// router mode, and lets you build, save as a track, or clear.
struct RoutePlannerView: View {
  @ObservedObject var model: RoutingModel
  let onSaved: (MWMTrackID) -> Void

  @State private var avoidTolls: Bool = OMPreferences.avoidTolls()
  @State private var avoidMotorways: Bool = OMPreferences.avoidMotorways()
  @State private var avoidFerries: Bool = OMPreferences.avoidFerries()
  @State private var avoidDirty: Bool = OMPreferences.avoidDirty()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header

      List {
        ForEach(0 ..< model.points.count, id: \.self) { i in
          pointRow(model.points[i])
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .onMove { source, destination in
          guard let from = source.first else { return }
          let to = from < destination ? destination - 1 : destination
          model.move(from: from, to: to)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .frame(minHeight: 24, maxHeight: 220)

      if model.isBuilt, let d = model.distance, let t = model.duration {
        Text("\(d) · \(t)").font(.subheadline).foregroundStyle(.secondary)
      }
      if let error = model.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }

      HStack(spacing: 8) {
        Button { model.build() } label: { Label("Build", systemImage: "arrow.triangle.turn.up.right.diamond") }
          .buttonStyle(.borderedProminent)
          .disabled(!model.canBuild || model.isBuilding)
        Button("Save as Track") { onSaved(model.saveAsTrack()) }
          .disabled(!model.isBuilt)
        Spacer()
        Button("Clear", role: .destructive) { model.clear() }
      }
    }
    .padding(14)
    .frame(width: 360)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(radius: 8)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Route").font(.headline)
      Spacer()
      if model.routerType == .car {
        Menu {
          Toggle("Avoid toll roads", isOn: Binding(
            get: { avoidTolls },
            set: { v in avoidTolls = v; OMPreferences.setAvoidTolls(v); if model.isBuilt { model.build() } }))
          Toggle("Avoid motorways", isOn: Binding(
            get: { avoidMotorways },
            set: { v in avoidMotorways = v; OMPreferences.setAvoidMotorways(v); if model.isBuilt { model.build() } }))
          Toggle("Avoid ferries", isOn: Binding(
            get: { avoidFerries },
            set: { v in avoidFerries = v; OMPreferences.setAvoidFerries(v); if model.isBuilt { model.build() } }))
          Toggle("Avoid unpaved roads", isOn: Binding(
            get: { avoidDirty },
            set: { v in avoidDirty = v; OMPreferences.setAvoidDirty(v); if model.isBuilt { model.build() } }))
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Driving options")
      }
      Picker("", selection: Binding(
        get: { model.routerType },
        set: { model.setRouterType($0) }
      )) {
        Label("Car", systemImage: "car.fill").tag(OMRouterType.car)
        Label("Walk", systemImage: "figure.walk").tag(OMRouterType.pedestrian)
        Label("Bike", systemImage: "bicycle").tag(OMRouterType.bicycle)
        Label("Transit", systemImage: "tram.fill").tag(OMRouterType.transit)
        Label("Ruler", systemImage: "ruler").tag(OMRouterType.ruler)
      }
      .labelsHidden().pickerStyle(.menu).fixedSize()
    }
  }

  private func pointRow(_ point: OMRoutePoint) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon(for: point.kind)).foregroundStyle(color(for: point.kind))
      Text(label(for: point)).lineLimit(1)
      Spacer()
      Button { model.remove(point) } label: { Image(systemName: "xmark.circle") }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
    }
    .font(.subheadline)
  }

  private func icon(for kind: OMRoutePointKind) -> String {
    switch kind {
    case .start: return "circle.fill"
    case .intermediate: return "smallcircle.filled.circle"
    case .finish: return "flag.fill"
    @unknown default: return "circle"
    }
  }

  private func color(for kind: OMRoutePointKind) -> Color {
    switch kind {
    case .start: return .green
    case .intermediate: return .blue
    case .finish: return .red
    @unknown default: return .gray
    }
  }

  private func label(for point: OMRoutePoint) -> String {
    let title = point.title.isEmpty ? String(format: "%.5f, %.5f", point.latitude, point.longitude) : point.title
    switch point.kind {
    case .start: return "Start · \(title)"
    case .intermediate: return "Stop · \(title)"
    case .finish: return "Finish · \(title)"
    @unknown default: return title
    }
  }
}
