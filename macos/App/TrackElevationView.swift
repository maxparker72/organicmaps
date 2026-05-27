import Charts
import SwiftUI

/// Elevation profile chart for a selected track (altitude vs. distance).
struct TrackElevationView: View {
  let trackId: MWMTrackID

  @State private var points: [ElevationPoint] = []

  struct ElevationPoint: Identifiable {
    let id = UUID()
    let distance: Double  // metres
    let altitude: Double  // metres
  }

  var body: some View {
    Group {
      if points.count > 1 {
        Chart(points) { point in
          AreaMark(x: .value("Distance", point.distance), y: .value("Altitude", point.altitude))
            .foregroundStyle(.green.opacity(0.25))
          LineMark(x: .value("Distance", point.distance), y: .value("Altitude", point.altitude))
            .foregroundStyle(.green)
        }
        .chartYAxisLabel("m")
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
    points = OMBookmarksHelper.elevationProfile(forTrack: trackId).map {
      ElevationPoint(distance: Double($0.pointValue.x), altitude: Double($0.pointValue.y))
    }
  }
}
