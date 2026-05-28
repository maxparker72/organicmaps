import AppKit
import Combine

/// Publishes the current Option modifier state so SwiftUI views can re-render
/// labels (e.g. "From here" → "Insert at front") while the key is held.
final class ModifierKeyMonitor: ObservableObject {
  @Published var isOptionPressed = false

  private var monitor: Any?

  init() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.isOptionPressed = event.modifierFlags.contains(.option)
      return event
    }
  }

  deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
  }
}
