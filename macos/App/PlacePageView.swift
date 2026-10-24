import AppKit
import SwiftUI

/// The right-hand info pane shown when a place is selected on the map.
struct PlacePageView: View {
  let info: OMPlaceInfo
  let onClear: () -> Void
  let onHide: () -> Void
  let onAddBookmark: () -> Void
  let onChanged: () -> Void
  let onDeleted: () -> Void
  let onSetStart: () -> Void
  let onPrepend: () -> Void
  let onAddStopAtEnd: () -> Void
  let onAddStopAtFront: () -> Void
  let onSetFinish: () -> Void
  let onAppend: () -> Void

  @State private var editing = false
  @State private var trackStats: OMTrackStats?
  @StateObject private var modifiers = ModifierKeyMonitor()

  private var isEditable: Bool { info.isBookmark || info.isTrack }

  /// Identifies the selected bookmark or track. The pane is reused across
  /// selections, so the editor is keyed on this and closed when it changes;
  /// otherwise a form loaded for one item could save onto the next (LIB-02).
  private var itemKey: String {
    info.isBookmark ? "b\(info.bookmarkId)" : info.isTrack ? "t\(info.trackId)" : ""
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if editing {
        EntityEditView(
          info: info,
          onSave: { editing = false; onChanged() },
          onCancel: { editing = false },
          onDelete: { editing = false; onDeleted() })
        .id(itemKey)
      } else {
        readContent
      }
    }
    .frame(width: 340)
    .background(.regularMaterial)
    .onAppear { loadTrackStats() }
    .onChange(of: info.trackId) { _, _ in loadTrackStats() }
    .onChange(of: itemKey) { _, _ in editing = false }
  }

  private func loadTrackStats() {
    trackStats = info.isTrack ? OMBookmarksHelper.trackStats(forTrack: info.trackId) : nil
  }

  private var readContent: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if !info.subtitle.isEmpty || info.hasDistance {
            summary
          }
          if info.isBookmark {
            Label("Saved to bookmarks", systemImage: "bookmark.fill")
              .font(.subheadline).foregroundStyle(.secondary)
          } else {
            Button(action: onAddBookmark) {
              Label("Add to Bookmarks", systemImage: "bookmark")
            }
            .buttonStyle(.borderedProminent)
          }
          HStack(spacing: 8) {
            Button {
              if modifiers.isOptionPressed { onPrepend() } else { onSetStart() }
            } label: {
              Label(modifiers.isOptionPressed ? "Insert at front" : "From here",
                    systemImage: "circle.fill")
            }
            .help("Set as start  ·  hold ⌥ to insert before the current start")

            Button {
              if modifiers.isOptionPressed { onAddStopAtFront() } else { onAddStopAtEnd() }
            } label: {
              Label(modifiers.isOptionPressed ? "Stop after start" : "Add stop",
                    systemImage: "plus.circle")
            }
            .help("Add a stop before the finish  ·  hold ⌥ to add right after the start")

            Button {
              if modifiers.isOptionPressed { onAppend() } else { onSetFinish() }
            } label: {
              Label(modifiers.isOptionPressed ? "Insert at end" : "To here",
                    systemImage: "flag.fill")
            }
            .help("Set as end  ·  hold ⌥ to insert after the current end")
          }
          .controlSize(.small)
          if info.isTrack {
            if let stats = trackStats {
              section("Statistics") { TrackStatsView(mode: .single(stats)) }
            }
            section("Elevation") { TrackElevationView(trackId: info.trackId) }
          }
          hoursSection
          contactSection
          detailsSection
          locationSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
  }

  // MARK: - Header & summary

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(info.title.isEmpty ? "Dropped pin" : info.title).font(.headline)
        if !info.secondaryTitle.isEmpty {
          Text(info.secondaryTitle).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Spacer()
      if isEditable && !editing {
        Button { editing = true } label: { Image(systemName: "pencil") }
          .buttonStyle(.borderless).help("Edit")
      }
      Button(action: onHide) { Image(systemName: "sidebar.right") }
        .buttonStyle(.borderless).help("Hide info pane")
      Button(action: onClear) { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(.borderless).help("Clear selection")
    }
    .padding(16)
  }

  private var summary: some View {
    HStack(spacing: 8) {
      if !info.subtitle.isEmpty {
        Text(info.subtitle).foregroundStyle(.secondary)
      }
      Spacer()
      if info.hasDistance, let distance = info.distanceString {
        HStack(spacing: 4) {
          Image(systemName: "arrow.up")
            .rotationEffect(.degrees(info.directionAzimuth))
          Text(distance)
          if let cardinal = info.directionCardinal { Text(cardinal).foregroundStyle(.secondary) }
        }
        .font(.subheadline)
      }
    }
  }

  // MARK: - Sections

  @ViewBuilder private var hoursSection: some View {
    if let hours = info.openingHours {
      section("Hours") { detail("Opening hours", hours) }
    }
  }

  @ViewBuilder private var contactSection: some View {
    let rows: [(String, String)] = [
      ("Phone", info.phone), ("Website", info.website), ("Menu", info.websiteMenu),
      ("Email", info.email), ("Facebook", info.facebook), ("Instagram", info.instagram),
      ("Twitter", info.twitter),
    ].compactMap { label, value in value.map { (label, $0) } }

    if !rows.isEmpty {
      section("Contact") {
        ForEach(rows, id: \.0) { detail($0.0, $0.1) }
      }
    }
  }

  @ViewBuilder private var detailsSection: some View {
    let rows: [(String, String)] = [
      ("Elevation", info.elevation), ("Stars", info.stars), ("Cuisine", info.cuisine),
      ("Operator", info.ppOperator), ("Brand", info.brand), ("Internet", info.internet),
      ("Wheelchair", info.wheelchair), ("Level", info.level), ("Capacity", info.capacity),
      ("Postcode", info.postcode), ("Wikipedia", info.wikipedia),
      ("Description", info.descriptionText),
    ].compactMap { label, value in value.map { (label, $0) } }

    if !rows.isEmpty {
      section("Details") {
        ForEach(rows, id: \.0) { detail($0.0, $0.1) }
      }
    }
  }

  private var locationSection: some View {
    section("Location") {
      if !info.address.isEmpty { detail("Address", info.address) }
      HStack {
        detail("Coordinates", coordinateString)
        Spacer()
        Button {
          let pb = NSPasteboard.general
          pb.clearContents()
          pb.setString(coordinateString, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless).help("Copy coordinates")
      }
      Button {
        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(info.latitude),\(info.longitude)") {
          NSWorkspace.shared.open(url)
        }
      } label: {
        Label("Open in Google Maps", systemImage: "arrow.up.forward.square")
      }
      Button {
        let link = OMBookmarksHelper.omLink(lat: info.latitude, lon: info.longitude,
                                            name: info.title.isEmpty ? "" : info.title)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(link, forType: .string)
      } label: {
        Label("Copy Organic Maps Link", systemImage: "link")
      }
    }
  }

  // MARK: - Building blocks

  private var coordinateString: String {
    String(format: "%.6f, %.6f", info.latitude, info.longitude)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
      content()
    }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}
