import SwiftUI

/// Transient preview sheet for a single bookmark or track. Triggered by
/// Cmd-Y or Space (when the navigator owns focus). Reuses the same stats
/// and elevation components as PlacePageView so the preview matches the
/// inspector, but stays compact and dismisses on Esc.
struct QuickLookView: View {
  let item: NavSelection
  let onClose: () -> Void

  @State private var trackStats: OMTrackStats?

  private var manager: BookmarksManager { BookmarksManager.shared() }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch item {
          case .bookmark(let id): bookmarkContent(id)
          case .track(let id): trackContent(id)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      HStack {
        Spacer()
        Button("Done", action: onClose)
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.borderedProminent)
      }
      .padding(12)
    }
    .frame(width: 420, height: 520)
    .onAppear(perform: load)
  }

  private func load() {
    if case .track(let id) = item {
      trackStats = OMBookmarksHelper.trackStats(forTrack: id)
    }
  }

  // MARK: - Header

  @ViewBuilder private var header: some View {
    HStack(spacing: 12) {
      switch item {
      case .bookmark(let id):
        let bm = manager.bookmark(withId: id)
        Circle().fill(Color(nsColor: bm.bookmarkColor)).frame(width: 16, height: 16)
        VStack(alignment: .leading, spacing: 2) {
          Text(bm.bookmarkName).font(.headline)
          Text("Bookmark").font(.caption).foregroundStyle(.secondary)
        }
      case .track(let id):
        let track = manager.track(withId: id)
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color(nsColor: track.trackColor))
          .frame(width: 20, height: 5)
        VStack(alignment: .leading, spacing: 2) {
          Text(track.trackName).font(.headline)
          Text("Track").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }

  // MARK: - Content per kind

  private func bookmarkContent(_ id: MWMMarkID) -> some View {
    let bm = manager.bookmark(withId: id)
    let coords = bm.locationCoordinate
    let listTitle = EntityEditor.lists()
      .first(where: { $0.categoryId == EntityEditor.bookmarkGroup(id) })?.title ?? "—"
    let tags = OMBookmarksHelper.tags(forBookmark: id).joined(separator: ", ")
    let region = OMBookmarksHelper.regions(forBookmark: id)
      .first.map { OMBookmarksHelper.displayName(forRegion: $0) } ?? "—"
    let description = EntityEditor.bookmarkDescription(id)
    let distance = OMBookmarksHelper.distanceFromCurrentPosition(
      toLat: coords.latitude, lon: coords.longitude)

    return VStack(alignment: .leading, spacing: 10) {
      labeled("Coordinates", String(format: "%.5f, %.5f", coords.latitude, coords.longitude))
      if let distance { labeled("Distance from you", distance) }
      labeled("List", listTitle)
      if !tags.isEmpty { labeled("Tags", tags) }
      if region != "—" { labeled("Region", region) }
      if !description.isEmpty { labeled("Description", description) }
    }
  }

  private func trackContent(_ id: MWMTrackID) -> some View {
    let listTitle = EntityEditor.lists()
      .first(where: { $0.categoryId == EntityEditor.trackGroup(id) })?.title ?? "—"
    let tags = OMBookmarksHelper.tags(forTrack: id).joined(separator: ", ")
    let region = OMBookmarksHelper.regions(forTrack: id)
      .first.map { OMBookmarksHelper.displayName(forRegion: $0) } ?? "—"
    let description = EntityEditor.trackDescription(id)

    return VStack(alignment: .leading, spacing: 14) {
      if let stats = trackStats {
        TrackStatsView(mode: .single(stats))
      }
      section("Elevation") { TrackElevationView(trackId: id) }
      VStack(alignment: .leading, spacing: 10) {
        labeled("List", listTitle)
        if !tags.isEmpty { labeled("Tags", tags) }
        if region != "—" { labeled("Region", region) }
        if !description.isEmpty { labeled("Description", description) }
      }
    }
  }

  // MARK: - Building blocks

  private func labeled(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      content()
    }
  }
}
