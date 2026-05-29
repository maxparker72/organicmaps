import Foundation

/// Observable wrapper around OMSearch. The text field binds to `query`; setting
/// it kicks off a live everywhere-search and republishes results as the engine
/// streams them. "Pins live" mode (Enter / category / history) additionally
/// runs a viewport search that the engine renders directly onto the map.
final class SearchModel: NSObject, ObservableObject, OMSearchDelegate {
  enum Tab: Hashable { case results, history, categories }

  @Published var query: String = "" {
    didSet { if !suppressQueryDidSet { onQueryChanged() } }
  }
  @Published var results: [OMSearchResult] = []
  @Published var history: [String] = []
  @Published var categories: [String] = []
  @Published var tab: Tab = .categories
  @Published var isSearching: Bool = false
  /// Mirrors OMSearch.pinsLive for the UI banner / Clear button visibility.
  @Published private(set) var pinsLive: Bool = false

  private var pendingCategoryFlag = false
  /// Used by runCategory/runHistory to set `query` without re-triggering the
  /// `didSet` everywhere-search; they go through showAllOnMap explicitly.
  private var suppressQueryDidSet = false

  override init() {
    super.init()
    OMSearch.shared().delegate = self
    refreshLists()
  }

  func refreshLists() {
    history = OMSearch.recentQueries()
    categories = OMSearch.categories()
  }

  func clearHistory() {
    OMSearch.clearHistory()
    refreshLists()
  }

  /// Live typing path. Runs only the everywhere search (best ranked matches
  /// for the dialog). Pins stay off until the user explicitly enables them.
  private func onQueryChanged() {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      setPinsLive(false)
      OMSearch.shared().clear()
      results = []
      isSearching = false
      tab = (history.isEmpty ? .categories : .history)
      return
    }
    // Don't auto-drop pins during refinement; the user keeps pins live until
    // they explicitly clear them or close the dialog. The viewport search
    // re-runs anyway because searchText also restarts it if pinsLive is on.
    tab = .results
    isSearching = true
    OMSearch.shared().searchText(trimmed, locale: locale(), isCategory: pendingCategoryFlag)
    pendingCategoryFlag = false
  }

  /// Category chip — engine treats it as a category browse and the user wants
  /// pins on the map immediately, so go straight to showAllOnMap.
  func runCategory(_ key: String) {
    pendingCategoryFlag = true
    setQuerySilently(key + " ")
    showAllOnMap()
  }

  /// History row — re-run a previous query with pins.
  func runHistory(_ text: String) {
    pendingCategoryFlag = false
    setQuerySilently(text)
    showAllOnMap()
  }

  /// Enter in the search box: save to history, re-run the query, and turn
  /// pins live so the engine drops up-to-200 viewport-bounded results onto
  /// the map. Pressing Enter again after zooming/panning re-runs against the
  /// new viewport (the engine's viewport search picks up the new bounds).
  func showAllOnMap() {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    OMSearch.shared().saveQuery(trimmed, locale: locale())
    isSearching = true
    tab = .results
    // searchText also restarts the viewport search when pinsLive is on, so
    // setting pinsLive first means the upcoming searchText call kicks off
    // both searches together (no extra round-trip).
    setPinsLive(true)
    OMSearch.shared().searchText(trimmed, locale: locale(), isCategory: pendingCategoryFlag)
    pendingCategoryFlag = false
    refreshLists()
  }

  /// Clear search pins from the map (engine viewport search is cancelled and
  /// its SEARCH marks are removed). Dialog stays open.
  func clearMap() {
    setPinsLive(false)
  }

  /// Hook used by ContentView on place-page changes. Viewport-search-active
  /// already suppresses the engine's tap-clear, so this is a no-op when pins
  /// are off; when on, it re-runs the viewport search as a cheap safety net.
  func refillPinsIfLive() {
    OMSearch.shared().refillPins()
  }

  /// User picked a result row. Suggestions update the text box; concrete
  /// results select on the map (place page opens via OMPlacePage delegate).
  func select(_ result: OMSearchResult) {
    if let suggestion = result.suggestion, !suggestion.isEmpty {
      query = suggestion
      return
    }
    let toSave = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !toSave.isEmpty {
      OMSearch.shared().saveQuery(toSave, locale: locale())
    }
    OMSearch.shared().selectResult(at: result.index)
    refreshLists()
  }

  // MARK: - OMSearchDelegate

  func searchResultsDidUpdate() {
    results = OMSearch.shared().results()
  }

  func searchDidComplete() {
    results = OMSearch.shared().results()
    isSearching = false
  }

  // MARK: - Helpers

  private func setPinsLive(_ on: Bool) {
    OMSearch.shared().pinsLive = on
    pinsLive = on
  }

  private func setQuerySilently(_ text: String) {
    suppressQueryDidSet = true
    query = text
    suppressQueryDidSet = false
  }

  private func locale() -> String {
    return Locale.current.identifier
  }
}
