import Charts
import SwiftUI

/// Elevation profile chart for a selected track (altitude vs. distance).
struct TrackElevationView: View {
  let trackId: MWMTrackID

  @State private var points: [ElevationPoint] = []
  @State private var units: OMUnits = OMPreferences.units()

  struct ElevationPoint: Identifiable {
    let id = UUID()
    let distance: Double  // in display units (km or mi)
    let altitude: Double  // in display units (m or ft)
  }

  private var distanceUnit: String { units == .imperial ? "mi" : "km" }
  private var altitudeUnit: String { units == .imperial ? "ft" : "m" }

  var body: some View {
    Group {
      if points.count > 1 {
        Chart(points) { point in
          AreaMark(x: .value("Distance", point.distance), y: .value("Altitude", point.altitude))
            .foregroundStyle(.green.opacity(0.25))
          LineMark(x: .value("Distance", point.distance), y: .value("Altitude", point.altitude))
            .foregroundStyle(.green)
        }
        .chartXAxisLabel(distanceUnit)
        .chartYAxisLabel(altitudeUnit)
        .frame(height: 130)
      } else {
        Text("No elevation data for this track.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear(perform: load)
    .onChange(of: trackId) { _, _ in load() }
  }

  private func load() {
    units = OMPreferences.units()
    let metersToMiles = 0.000621371192
    let metersToKm = 0.001
    let metersToFeet = 3.2808399
    let distanceScale = units == .imperial ? metersToMiles : metersToKm
    let altitudeScale = units == .imperial ? metersToFeet : 1.0
    points = OMBookmarksHelper.elevationProfile(forTrack: trackId).map {
      ElevationPoint(
        distance: Double($0.pointValue.x) * distanceScale,
        altitude: Double($0.pointValue.y) * altitudeScale)
    }
  }
}
