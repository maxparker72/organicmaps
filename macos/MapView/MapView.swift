import AppKit
import SwiftUI

/// SwiftUI wrapper around the AppKit/Metal map view.
struct MapView: NSViewRepresentable {
  func makeNSView(context: Context) -> OMMapView {
    return OMMapView(frame: .zero)
  }

  func updateNSView(_ nsView: OMMapView, context: Context) {}
}
