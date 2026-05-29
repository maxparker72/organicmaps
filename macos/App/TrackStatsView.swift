import SwiftUI

/// Vertically-stacked label/value grid for one or more track statistics.
/// Used by PlacePageView (single track) and MultiSelectionInspectorView /
/// ListInfoView (aggregate over a set of tracks).
///
/// The engine's per-track formatted strings (TrackStatistics::GetFormatted*)
/// are unit-correct, so we display them verbatim for the single-track case.
/// Aggregates have to sum raw meters/seconds and format in Swift; we honour
/// the same OMUnits preference the engine uses elsewhere.
struct TrackStatsView: View {
  enum Mode {
    case single(OMTrackStats)
    case aggregate([OMTrackStats])
  }

  let mode: Mode

  @State private var units: OMUnits = OMPreferences.units()

  private var dateFormatter: DateFormatter {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
  }

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
      ForEach(rows, id: \.0) { label, value in
        GridRow {
          Text(label).font(.caption).foregroundStyle(.secondary)
          Text(value).font(.subheadline).textSelection(.enabled).gridColumnAlignment(.leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { units = OMPreferences.units() }
  }

  private var rows: [(String, String)] {
    switch mode {
    case .single(let s): return singleRows(s)
    case .aggregate(let arr): return aggregateRows(arr)
    }
  }

  // MARK: - Single

  private func singleRows(_ s: OMTrackStats) -> [(String, String)] {
    var out: [(String, String)] = [("Length", s.formattedLength)]
    if s.hasDuration {
      out.append(("Duration", s.formattedDuration))
    }
    if s.hasElevation {
      out.append(("Ascent", s.formattedAscent))
      out.append(("Descent", s.formattedDescent))
      out.append(("Min elevation", s.formattedMinElevation))
      out.append(("Max elevation", s.formattedMaxElevation))
    }
    if s.pointCount > 0 {
      out.append(("Points", numberFormatter.string(from: NSNumber(value: s.pointCount)) ?? "\(s.pointCount)"))
    }
    if let start = s.startDate, let end = s.endDate {
      out.append(("Recorded", recordedSpan(start, end)))
    }
    return out
  }

  // MARK: - Aggregate

  private func aggregateRows(_ arr: [OMTrackStats]) -> [(String, String)] {
    guard !arr.isEmpty else { return [] }
    let totalLength = arr.reduce(0) { $0 + $1.lengthMeters }
    let totalDuration = arr.reduce(0) { $0 + (max($1.durationSeconds, 0)) }
    let withElevation = arr.filter { $0.hasElevation }
    let totalAscent = withElevation.reduce(0) { $0 + $1.ascentMeters }
    let totalDescent = withElevation.reduce(0) { $0 + $1.descentMeters }
    let totalPoints = arr.reduce(0) { $0 + $1.pointCount }

    var out: [(String, String)] = [
      ("Tracks", "\(arr.count)"),
      ("Total length", OMBookmarksHelper.formatDistance(meters: totalLength)),
    ]
    if totalDuration > 0 {
      out.append(("Total duration", formatDuration(totalDuration)))
    }
    if !withElevation.isEmpty {
      out.append(("Total ascent", formatAltitude(totalAscent)))
      out.append(("Total descent", formatAltitude(totalDescent)))
      let mins = withElevation.map(\.minElevationMeters).min() ?? 0
      let maxs = withElevation.map(\.maxElevationMeters).max() ?? 0
      out.append(("Min elevation", formatAltitude(mins)))
      out.append(("Max elevation", formatAltitude(maxs)))
    }
    out.append(("Points", numberFormatter.string(from: NSNumber(value: totalPoints)) ?? "\(totalPoints)"))
    if let span = dateSpan(arr) {
      out.append(("Recorded", span))
    }
    return out
  }

  // MARK: - Formatting

  private func formatAltitude(_ meters: Double) -> String {
    if units == .imperial {
      let ft = meters * 3.2808399
      return "\(Int(ft.rounded())) ft"
    }
    return "\(Int(meters.rounded())) m"
  }

  private func formatDuration(_ seconds: Double) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h == 0 { return "\(m) m" }
    return "\(h) h \(m) m"
  }

  private func recordedSpan(_ start: Date, _ end: Date) -> String {
    let df = dateFormatter
    let calendar = Calendar.current
    if calendar.isDate(start, inSameDayAs: end) { return df.string(from: start) }
    return "\(df.string(from: start)) – \(df.string(from: end))"
  }

  private func dateSpan(_ arr: [OMTrackStats]) -> String? {
    let starts = arr.compactMap(\.startDate)
    let ends = arr.compactMap(\.endDate)
    guard let earliest = starts.min(), let latest = ends.max() else { return nil }
    return recordedSpan(earliest, latest)
  }

  private var numberFormatter: NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
  }
}
