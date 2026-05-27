import Foundation

/// Observable mirror of the engine's map-overlay layers. Toggles drive
/// CoreApi's MapOverlayManager; the observer keeps these in sync with engine
/// state (e.g. a layer disabling itself when it has no data for the region).
final class LayersModel: NSObject, ObservableObject, MapOverlayManagerObserver {
  @Published var subway = false
  @Published var isolines = false
  @Published var outdoor = false
  @Published var hiking = false
  @Published var cycling = false

  override init() {
    super.init()
    MapOverlayManager.add(self)
    refresh()
  }

  deinit {
    MapOverlayManager.remove(self)
  }

  func onMapOverlayUpdated() {
    refresh()
  }

  private func refresh() {
    subway = MapOverlayManager.transitEnabled()
    isolines = MapOverlayManager.isoLinesEnabled()
    outdoor = MapOverlayManager.outdoorEnabled()
    hiking = MapOverlayManager.hikingEnabled()
    cycling = MapOverlayManager.cyclingEnabled()
  }

  func setSubway(_ on: Bool) { MapOverlayManager.setTransitEnabled(on) }
  func setIsolines(_ on: Bool) { MapOverlayManager.setIsoLinesEnabled(on) }
  func setOutdoor(_ on: Bool) { MapOverlayManager.setOutdoorEnabled(on) }
  func setHiking(_ on: Bool) { MapOverlayManager.setHikingEnabled(on) }
  func setCycling(_ on: Bool) { MapOverlayManager.setCyclingEnabled(on) }
}
