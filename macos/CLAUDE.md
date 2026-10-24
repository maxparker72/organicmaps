# macOS app (BDSM)

Native SwiftUI Mac app on the Organic Maps engine. Read these first:

- `docs/SPEC.md`: features, IDs, acceptance checks. Behaviour changes start here.
- `docs/ARCHITECTURE.md`: layers, ownership, threading rules, engine patches.
- `docs/DECISIONS.md`: why things are the way they are. Don't reverse a decision without adding a new one.

The repo-root `CLAUDE.md` covers engine conventions (C++ style, `libs/` layering, test macros).

## Build

```sh
cd macos && xcodegen generate          # after editing project.yml or adding any source file
xcodebuild -project macos/OMapsDesktop.xcodeproj -scheme OMapsDesktop -configuration Debug -destination 'platform=macOS' build
```

- Xcode updates remove the Metal toolchain. If `shaders_metal` fails with "missing Metal Toolchain": `xcodebuild -downloadComponent MetalToolchain`.
- If `xcode-select -p` points at CommandLineTools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- The pbxproj is generated and gitignored. Sources are globbed by directory, so a new file isn't built until you rerun xcodegen.
- Debug runs read engine resources from the repo's `data/` via `MWM_RESOURCES_DIR` (set in the scheme). Release bundles them.
- `minizip.framework` is dynamic and must stay `embed: true`.
- `shaders_metal.metallib` is copied into Resources by a post-build script; the map is blank without it.

## Rules for this code

- Engine calls happen on the main thread. `BookmarkManager` asserts it.
- Check that a list exists (`HasBmCategory`) before passing a group id to the engine. Both 0 and `kml::kInvalidMarkGroupId` abort.
- Group bulk changes in one `GetEditSession()`.
- Pass `reorderIntermediatePoints = false` to `AddRoutePoint` when the bridge picks the index.
- Use the place's coordinate (`info.GetMercator()`), not the click point (`GetBuildInfo().m_mercator`).
- Commits: `[macos] <SPEC-ID>: <change>`, for example `[macos] LIB-06: keep imported track widths`.
