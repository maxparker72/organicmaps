import Foundation

/// State for the route planner overlay. Routes build async; the helper's
/// delegate notifies us when they finish.
final class RoutingModel: NSObject, ObservableObject, OMRoutingDelegate {
  @Published var points: [OMRoutePoint] = []
  @Published var routerType: OMRouterType = .car
  @Published var isBuilt = false
  @Published var isBuilding = false
  @Published var distance: String?
  @Published var duration: String?
  @Published var errorMessage: String?

  override init() {
    super.init()
    OMRoutingHelper.shared().delegate = self
    routerType = OMRoutingHelper.routerType()
    refresh()
  }

  var hasPoints: Bool { !points.isEmpty }
  var canBuild: Bool { points.contains { $0.kind == .start } && points.contains { $0.kind == .finish } }

  func setRouterType(_ type: OMRouterType) {
    OMRoutingHelper.setRouterType(type)
    routerType = type
    if canBuild { build() }
  }

  func build() {
    errorMessage = nil
    isBuilding = true
    OMRoutingHelper.build()
  }

  func clear() {
    OMRoutingHelper.clear()
    errorMessage = nil
  }

  func remove(_ point: OMRoutePoint) {
    OMRoutingHelper.removePoint(point)
  }

  func move(from: Int, to: Int) {
    OMRoutingHelper.movePoint(from: from, to: to)
    if canBuild { build() }
  }

  @discardableResult
  func saveAsTrack() -> MWMTrackID {
    OMRoutingHelper.saveAsTrack()
  }

  // MARK: - OMRoutingDelegate

  func routingDidUpdate() { refresh() }
  func routingDidFinishBuilding(_ success: Bool, message: String?) {
    isBuilding = false
    errorMessage = success ? nil : message
    refresh()
  }

  private func refresh() {
    points = OMRoutingHelper.points()
    isBuilt = OMRoutingHelper.isRouteBuilt()
    isBuilding = OMRoutingHelper.isRouteBuilding()
    distance = OMRoutingHelper.totalDistanceString()
    duration = OMRoutingHelper.totalDurationString()
  }
}
