import Foundation

/// Two-way binding to OMPreferences for the Settings window.
final class PreferencesModel: ObservableObject {
  struct MapLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
  }

  let availableMapLanguages: [MapLanguage] = {
    OMPreferences.supportedMapLanguages().compactMap {
      guard let code = $0["code"], let name = $0["name"] else { return nil }
      return MapLanguage(code: code, name: name)
    }
  }()

  @Published var units: OMUnits {
    didSet { if oldValue != units { OMPreferences.setUnits(units) } }
  }
  @Published var mapLanguage: String {
    didSet { if oldValue != mapLanguage { OMPreferences.setMapLanguageCode(mapLanguage) } }
  }
  @Published var transliteration: Bool {
    didSet { if oldValue != transliteration { OMPreferences.setTransliteration(transliteration) } }
  }
  @Published var largeFonts: Bool {
    didSet { if oldValue != largeFonts { OMPreferences.setLargeFonts(largeFonts) } }
  }

  @Published var mapStyle: OMMapStyleKind {
    didSet { if oldValue != mapStyle { OMPreferences.setMapStyle(mapStyle) } }
  }
  @Published var buildings3D: Bool {
    didSet { if oldValue != buildings3D { OMPreferences.setBuildings3D(buildings3D) } }
  }
  @Published var bookmarkPlacement: OMBookmarkTextPlacement {
    didSet { if oldValue != bookmarkPlacement { OMPreferences.setBookmarkTextPlacement(bookmarkPlacement) } }
  }

  @Published var showDownloadedRegions: Bool {
    didSet { if oldValue != showDownloadedRegions { OMPreferences.setShowDownloadedRegions(showDownloadedRegions) } }
  }

  @Published var defaultRouter: Int {
    didSet { if oldValue != defaultRouter { OMPreferences.setDefaultRouterType(defaultRouter) } }
  }
  @Published var avoidTolls: Bool {
    didSet { if oldValue != avoidTolls { OMPreferences.setAvoidTolls(avoidTolls) } }
  }
  @Published var avoidMotorways: Bool {
    didSet { if oldValue != avoidMotorways { OMPreferences.setAvoidMotorways(avoidMotorways) } }
  }
  @Published var avoidFerries: Bool {
    didSet { if oldValue != avoidFerries { OMPreferences.setAvoidFerries(avoidFerries) } }
  }
  @Published var avoidDirty: Bool {
    didSet { if oldValue != avoidDirty { OMPreferences.setAvoidDirty(avoidDirty) } }
  }

  @Published var fileLogging: Bool {
    didSet { if oldValue != fileLogging { OMPreferences.setFileLogging(fileLogging) } }
  }

  init() {
    units = OMPreferences.units()
    let storedLang = OMPreferences.mapLanguageCode()
    let knownCodes = Set(availableMapLanguages.map { $0.code })
    if knownCodes.contains(storedLang) {
      mapLanguage = storedLang
    } else {
      mapLanguage = "en"
      OMPreferences.setMapLanguageCode("en")  // persist fallback so the rest of the app agrees
    }
    transliteration = OMPreferences.transliteration()
    largeFonts = OMPreferences.largeFonts()
    mapStyle = OMPreferences.mapStyle()
    buildings3D = OMPreferences.buildings3D()
    bookmarkPlacement = OMPreferences.bookmarkTextPlacement()
    showDownloadedRegions = OMPreferences.showDownloadedRegions()
    defaultRouter = OMPreferences.defaultRouterType()
    avoidTolls = OMPreferences.avoidTolls()
    avoidMotorways = OMPreferences.avoidMotorways()
    avoidFerries = OMPreferences.avoidFerries()
    avoidDirty = OMPreferences.avoidDirty()
    fileLogging = OMPreferences.fileLogging()
  }
}
