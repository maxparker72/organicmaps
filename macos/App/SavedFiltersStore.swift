import Foundation

extension Notification.Name {
  /// Posted by `SavedFiltersStore` when its filters or active selection
  /// change. Lets stale @StateObject instances re-load from UserDefaults
  /// when there are multiple stores in flight (the singleton + per-Window
  /// instances created by SwiftUI scenes).
  static let omSavedFiltersChanged = Notification.Name("omSavedFiltersChanged")
}

/// Persists named filter definitions to UserDefaults so the user can
/// re-apply complex queries without rebuilding them. Singleton so the
/// navigator, filter window, and Filter menu all observe the same state.
/// Tracks an optional "active" filter id so UI surfaces can show which
/// saved filter (if any) is currently applied.
final class SavedFiltersStore: ObservableObject {
  static let shared = SavedFiltersStore()

  @Published private(set) var filters: [SavedFilter] = []
  @Published private(set) var activeFilterId: UUID?

  private let filtersKey = "OMSavedFilters"
  private let activeKey = "OMSavedFiltersActive"
  private var changeObserver: NSObjectProtocol?

  init() {
    load()
    // Cross-instance sync: when the singleton mutates we re-broadcast so any
    // ad-hoc store (created via @StateObject inside a Scene) can re-load.
    changeObserver = NotificationCenter.default.addObserver(
      forName: .omSavedFiltersChanged, object: nil, queue: .main) { [weak self] note in
      guard let self, (note.object as? AnyObject) !== self else { return }
      self.load()
    }
  }

  deinit {
    if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
  }

  // MARK: - Mutations

  func save(_ filter: SavedFilter) {
    if let i = filters.firstIndex(where: { $0.id == filter.id }) {
      filters[i] = filter
    } else {
      filters.append(filter)
    }
    persistAndBroadcast()
  }

  func delete(_ id: UUID) {
    filters.removeAll { $0.id == id }
    if activeFilterId == id { activeFilterId = nil }
    persistAndBroadcast()
  }

  func rename(_ id: UUID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let i = filters.firstIndex(where: { $0.id == id }) else { return }
    filters[i].name = trimmed
    persistAndBroadcast()
  }

  /// Mark a saved filter as the one whose visibility state is currently
  /// active. Surfaces can show a checkmark next to it. Manual visibility
  /// changes elsewhere may make this stale; callers can clear it.
  func setActive(_ id: UUID?) {
    activeFilterId = id
    persistAndBroadcast()
  }

  // MARK: - Persistence

  private func load() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: filtersKey),
       let decoded = try? JSONDecoder().decode([SavedFilter].self, from: data) {
      filters = decoded
    } else {
      filters = []
    }
    if let s = defaults.string(forKey: activeKey), let id = UUID(uuidString: s) {
      activeFilterId = id
    } else {
      activeFilterId = nil
    }
  }

  private func persistAndBroadcast() {
    let defaults = UserDefaults.standard
    if let data = try? JSONEncoder().encode(filters) {
      defaults.set(data, forKey: filtersKey)
    }
    if let id = activeFilterId {
      defaults.set(id.uuidString, forKey: activeKey)
    } else {
      defaults.removeObject(forKey: activeKey)
    }
    NotificationCenter.default.post(name: .omSavedFiltersChanged, object: self)
  }
}
