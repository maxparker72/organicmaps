# Architecture

The Mac app is a native shell around the Organic Maps C++ engine (`libs/`). Mac code lives in the top two layers. The layers below are upstream, with a few small patches.

```
SwiftUI app            macos/App        Views, ObservableObject models, stores
   │  calls (bridging header)      ▲ NotificationCenter / observer callbacks
OM* bridges            macos/MapView    Objective-C++ class methods over GetFramework()
CoreApi                iphone/CoreApi   Shared with iOS (MWMBookmarksManager, MWMBookmark, MWMTrack)
   │  GetFramework()
Framework              libs/map         BookmarkManager, SearchAPI, RoutingManager, Storage
Engine libraries       libs/*, 3party   search, routing, storage, indexer, kml, platform, …
Rendering              libs/drape       Metal backend → MetalContextFactory (iOS file) → CAMetalLayer
```

## Rules

**Threading.** Every engine call happens on the main thread. `BookmarkManager` asserts this with `CHECK_THREAD_CHECKER`. The engine delivers search results, place-page events, storage notifications, viewport changes and routing callbacks on the main thread, through `RunTask(Gui)`. New Swift models are `@MainActor`.

**Ids.**
- Check a list exists with `HasBmCategory` before passing its id anywhere. Both 0 and `kml::kInvalidMarkGroupId` abort.
- Bookmark and track ids (`kml::MarkId`, `kml::TrackId`) are regenerated on every launch, because text KML doesn't store them. Never persist them. To refer to an item across launches, store a UUID in its KML properties.

**Edits.**
- Make bulk changes inside one `GetEditSession()`, which ends with one save and one notification.
- Only touch items that actually change. Calling `SetIsVisible` or `SetColor` with the current value still dirties the item and rewrites its KML file.

**Engine defaults to know.**
- `AddRoutePoint(data, reorderIntermediatePoints = true)` re-sorts stops. Pass `false` when the bridge picks the index.
- `Track::SetColor` writes only `m_rgba` on layer 0. Set both `m_predefinedColor` and `m_rgba` on every layer.
- `Bookmark::SetIsVisible` is runtime-only. Hidden bookmarks reappear after a relaunch unless `m_data.m_visible` is also set.
- `DeactivateMapSelection` clears the search pins unless viewport search is active, so the desktop refills them when the place page closes (`OMSearch.refillPins`).
- After an import, `assignPaletteColorsToUncoloredBookmarks` gives bookmarks with `PredefinedColor::None` the nearest palette entry. Upstream has since added `GetCustomColor()` for custom bookmark colors. If upstream stores those as None plus RGBA, this repair would overwrite them, so re-check it during the rebase (T-030).
- `GetBuildInfo().m_mercator` is the click point. Use the place's own coordinate (`info.GetMercator()`) for bookmarks, route stops and links.

## Lifecycle

**Today.** `OMMapView` creates the drape engine in `viewDidMoveToWindow` and owns the `MetalContextFactory`. Nothing tears the engine down. Each SwiftUI window creates its own set of models in `ContentView`.

**Target** (D-08):
- An app-lifetime `MapEngine` object owns the context factory.
- It disables rendering when the window is hidden or minimized, and destroys the engine before the factory is released.
- The main scene is a single `Window`, and models are created once at app level.

## Where data lives

| Data | Stored in | Notes |
|---|---|---|
| Lists, bookmarks, tracks, descriptions, colors | KML files in the data folder | Written by the engine |
| Tags | KML item properties, `tags` key, `;`-separated | Travel with exports (D-06) |
| Projects | KML lists marked with a kind property; members tagged `project:<uuid>` | Hide the `project:` prefix in the UI |
| Track visibility | KML `mwm:visibility` | Via the fork's `track.hpp` patch |
| Bookmark visibility | Runtime only | Known gap (R-B10) |
| Saved filters, active filter, navigator view mode, data folder override | UserDefaults | |
| Downloaded maps | Data folder, `<version>/` subfolder | |
| Engine resources (styles, fonts, World.mwm) | App bundle Resources in Release; the repo's `data/` in Debug | |

## Events

**Today.**
- The engine's observer callbacks (`MWMBookmarksManager`) trigger each model's `refresh()`.
- Writes through `OMBookmarksHelper` don't fire those observers, so the code posts its own notifications: `.omBookmarkItemsChanged`, `.omTagsChanged` and `.omItemVisibilityChanged`.
- Menu commands also go through NotificationCenter: `.omFindInLibrary`, `.omToggleQuickLook` and `.omSelectMatchingFilter`.

**Target.**
- One `LibraryStore` subscribes to a single engine-changed signal and publishes value-type rows.
- Menu commands use `FocusedValue`.
- See REVIEW-2026-10.md, "Recommended refactors".

## Engine patches (outside `macos/`)

Keep this table current. Each row costs time on every upstream sync (D-05).

| Patch | Files | Purpose | Upstream plan |
|---|---|---|---|
| UIKit/AppKit shim | `iphone/CoreApi/CoreApi/Common/TargetConditionalUI.h` + 7 headers | Compile CoreApi for macOS | Offer upstream if they want a Mac target |
| Metal drawable guard | `libs/drape/metal/metal_base_context.mm` | Skip a frame when the layer has no drawable | Offer as a bug-fix PR |
| Track visibility | `libs/map/track.hpp`, `libs/drape_frontend/*` | Hide tracks individually | Superseded upstream: adopt their `IsVisible()` on rebase |
| Qt-free file listing | `libs/platform/platform_qt.cpp` | Avoid linking Qt in the Mac app | Fork-only |
| Exclude iOS texture file | `xcode/drape/drape.xcodeproj` | Don't compile `hw_texture_ios.mm` for macOS | Fork-only |

## Build and packaging

- **Project.** `macos/project.yml` is the XcodeGen spec (D-04). It references 35 upstream library projects under `xcode/` and builds CoreApi as a static framework.
- **Release builds** bundle the engine data and the Metal shader library, so the app runs offline.
- **Known gaps:**
  - arm64-only (R-E7)
  - no hardened runtime (R-E8)
  - hard-coded scheme paths (R-E3)
  - version stored in two places (R-E5)
