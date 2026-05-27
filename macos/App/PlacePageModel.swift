import Foundation

/// Holds the currently selected place for the info pane. Driven by the engine's
/// map-selection events via OMPlacePage.
final class PlacePageModel: NSObject, ObservableObject, OMPlacePageDelegate {
  @Published var info: OMPlaceInfo?
  /// Bumped on each fresh selection so the UI can re-reveal a manually-hidden pane.
  @Published var openToken: Int = 0

  private let placePage = OMPlacePage()

  override init() {
    super.init()
    placePage.delegate = self
  }

  func start() {
    placePage.start()
  }

  func clearSelection() {
    placePage.clearSelection()
  }

  // MARK: - OMPlacePageDelegate

  func placePageDidOpen(_ info: OMPlaceInfo) {
    self.info = info
    openToken &+= 1
  }

  func placePageDidUpdate(_ info: OMPlaceInfo) {
    self.info = info
  }

  func placePageDidClose() {
    info = nil
  }
}
