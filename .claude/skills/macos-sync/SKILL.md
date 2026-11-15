---
name: macos-sync
description: Merge the latest upstream Organic Maps master into the Mac app branch (macos-experiment), fix what upstream broke, and verify the app still builds, launches and keeps the user's data. Use when asked to sync, update from upstream, pull community changes, or check how far behind upstream the Mac app is.
argument-hint: "[check]"
---

# Sync the Mac app with upstream

The Mac app lives on `macos-experiment` in the fork (`origin`, SSH alias `parker-solutions`).
Upstream is `upstream` (github.com/organicmaps/organicmaps). Policy: merge, never rebase (D-11).
Read `macos/CLAUDE.md` and the "Engine patches" table in `macos/docs/ARCHITECTURE.md` first.

With the argument `check`, do only step 1 and report; change nothing.

## 1. Measure

```sh
git fetch upstream
git rev-list --count $(git merge-base macos-experiment upstream/master)..upstream/master   # commits behind
git merge-tree --write-tree --name-only macos-experiment upstream/master | sed -n '2,/^$/p'  # conflicting files
```

Also list upstream changes that tend to break the Mac build even without conflicts:

```sh
B=$(git merge-base macos-experiment upstream/master)
git diff --stat "${B}" upstream/master -- xcode/omim.xcworkspace iphone/CoreApi libs/map/bookmark_manager.hpp \
  libs/map/bookmark.hpp libs/map/track.hpp libs/storage/storage.hpp libs/search/search_params.hpp
```

Note: in zsh, write `"${B}:path"`, not `$B:path` (`:l`, `:h` etc. are history modifiers).

## 2. Protect the user's data

The Debug scheme runs against the user's real library. Before the first launch of a merged build:

```sh
D="$HOME/Library/Application Support/mapo-backups/pre-sync-$(date +%F)"
mkdir -p "$D" && cp -cR "$HOME/Library/Application Support/OMapsDesktop/bookmarks" "$D/"
```

(`cp -c` makes an APFS clone: instant, no extra space.) Maps can be re-downloaded and aren't backed up.
If the data folder has moved (rename to mapo), use the path from `MWM_WRITABLE_DIR` in `macos/project.yml`.

## 3. Merge on a throwaway branch

```sh
git config rerere.enabled true; git config rerere.autoupdate true   # once per clone
git switch -c sync/upstream-$(date +%F) macos-experiment
git merge --no-ff --no-commit upstream/master
git submodule sync -q && git submodule update --init --recursive
```

Resolve conflicts with these rules:
- Upstream wins in `libs/` unless a row in the Engine patches table says the fork must keep something.
  If upstream now implements what a fork patch did, take upstream's and delete the fork's (update the table).
- Keep fork-only branches (`#ifdef OMIM_OS_MAC` in `platform_qt.cpp`) on top of upstream's code in the `#else`.
- `.gitignore`: keep both sides.
- After resolving, check files that merged *cleanly* but touch the same API: duplicate declarations
  (e.g. two `IsVisible()`) compile-fail later. `git diff "${B}" HEAD -- libs iphone xcode` shows the fork's patches.

## 4. Build until green

```sh
cd macos && xcodegen generate && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project macos/OMapsDesktop.xcodeproj \
  -scheme OMapsDesktop -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E 'error:|BUILD'
```

Known kinds of breakage, cheapest checks first:
- **Library projects added/removed upstream.** Compare `macos/project.yml` `projectReferences` and
  `dependencies` with the projects in `xcode/omim.xcworkspace/contents.xcworkspacedata` and the `lib*.a`
  linked by `iphone/Maps/Maps.xcodeproj`. Delete stale `xcode/<lib>/` folders that only hold `xcuserdata`.
- **UIKit in CoreApi headers.** `grep -rlnE '#import <UIKit/' iphone/CoreApi/CoreApi | grep -v TargetConditionalUI`
  — replace each with `#import "TargetConditionalUI.h"`. iOS-only API in `.mm` files gets `#if TARGET_OS_IPHONE`.
- **Engine/CoreApi API changes in `macos/MapView/*.mm` and `macos/App/*.swift`.** Find the upstream commit
  (`git log upstream/master -S'<removed symbol>'`) and copy what upstream's iOS code does now
  (`iphone/CoreApi`, `iphone/Maps`). Prefer a small helper in `macos/` over re-adding an engine API.
  Re-add engine code only when the Mac app needs a capability upstream removed, and add it to the patch table.
- A change that alters user-visible behaviour or stored data is a decision: add a `D-xx` entry to
  `macos/docs/DECISIONS.md`, and ask the user if it isn't clearly a like-for-like port.

## 5. Verify, not just compile

1. Launch through LaunchServices (a bare binary launch may show no window):
   ```sh
   APP=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project macos/OMapsDesktop.xcodeproj \
     -scheme OMapsDesktop -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ CODESIGNING_FOLDER_PATH /{print $2}')
   open -n --env MWM_RESOURCES_DIR="$PWD/data" --env "MWM_WRITABLE_DIR=<from project.yml>" \
     --stdout "$LOG" --stderr "$LOG" "$APP"
   ```
2. After ~15 s: process alive; `grep -E '^E\(|^C\(|ASSERT|CHECK' "$LOG"` is empty; a `screencapture -x`
   shows the map with bookmarks in their colors.
3. `diff -rq <backup>/bookmarks <data dir>/bookmarks`: unchanged files mean the new engine read the
   library without rewriting it. If files changed, find out why before going further.
4. Don't kill other running copies of the app (the user's installed one runs from `/Applications`).

## 6. Land it

```sh
git commit -s    # subject: [macos] Merge upstream master (<N> commits, <date>)
                 # body: conflict choices + each Mac adaptation; end with the attribution lines
git switch macos-experiment && git merge --ff-only sync/upstream-<date>
git push origin macos-experiment && git branch -d sync/upstream-<date>
```

Commit doc updates (patch table, decisions) separately. Then update the project tracker
(https://claude.ai/artifact/Uv29HhZD5wFnLcfPzremDW, via ArtifactData) and the memory note's "behind upstream" count.

## Report

Tell the user: commits merged, conflicts and how each was resolved, Mac code changed and why,
any behaviour change, verification results, and anything left for follow-up (as tracker items).
