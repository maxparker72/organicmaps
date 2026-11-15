---
name: macos-release
description: Build a Release of the Mac app (mapo), sign it for this Mac, install it to /Applications and check that it runs. Use when asked to release, publish, install, ship, or update the installed copy of mapo.
argument-hint: "[--no-bump]"
---

# Release mapo to this Mac

mapo is for personal use: builds are ad-hoc signed and installed locally (DECISIONS D-10, tracker T-008).
Notarization and DMGs are out of scope until the app is shared (SPEC PLAT-03).
Read `macos/CLAUDE.md` first. Paths below are relative to the repo root.

## 1. Preflight

- `git status --short -- macos libs iphone xcode` is empty, or every change is committed. A release
  must match a commit, so the installed build can be traced back to its source.
- Usually you're on `macos-experiment`. If upstream has moved a lot (`/macos-sync check`), offer to sync first.

## 2. Version

The version lives only in `MARKETING_VERSION` in `macos/project.yml`, as `YYYY.MM.DD` (upstream's format;
the engine sends it to the map servers). `CURRENT_PROJECT_VERSION` is the build number for that day.

- New day: set `MARKETING_VERSION` to today and `CURRENT_PROJECT_VERSION` to `"1"`.
- Same day as the current version: increment `CURRENT_PROJECT_VERSION`.
- Skip this step with `--no-bump` (rebuild of the same version).

Commit it: `[macos] Release <version> (<build>)`, signed off (`git commit -s`), with the attribution lines.

## 3. Build

```sh
cd macos && xcodegen generate && cd ..
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project macos/mapo.xcodeproj -scheme mapo \
  -configuration Release -destination 'platform=macOS' -derivedDataPath macos/build-release build 2>&1 \
  | grep -E 'error:|BUILD'
APP=macos/build-release/Build/Products/Release/mapo.app
```

If the "Bundle engine data" script fails with `required data item missing`, upstream renamed a file in `data/`:
update the list in `project.yml` to match the `data/` files in `iphone/Maps/Maps.xcodeproj`.

## 4. Check the bundle before installing

```sh
plutil -p "$APP/Contents/Info.plist" | grep -E 'CFBundleIdentifier|ShortVersion|CFBundleVersion'
ls "$APP/Contents/Resources/shaders_metal.metallib" "$APP/Contents/Resources/World.mwm"
codesign --verify --deep --strict "$APP" && codesign -dv "$APP" 2>&1 | grep Signature   # Signature=adhoc
```

Stop if any check fails. `spctl` reports "rejected" for ad-hoc builds; that's expected and harmless for an
app built on this Mac (no quarantine flag).

## 5. Install

mapo must not be running while it's replaced, and two copies must never run at once (they share the data
folder). If `pgrep -f '/Applications/mapo.app'` finds it, ask the user to quit it (Cmd-Q); don't kill it.

```sh
rm -rf /Applications/mapo.app.previous
[ -d /Applications/mapo.app ] && mv /Applications/mapo.app /Applications/mapo.app.previous
ditto "$APP" /Applications/mapo.app
codesign --verify --deep --strict /Applications/mapo.app
```

`mapo.app.previous` is the rollback: `rm -rf /Applications/mapo.app && mv /Applications/mapo.app.previous /Applications/mapo.app`.

## 6. Smoke test

```sh
open /Applications/mapo.app
sleep 15
pgrep -lf '/Applications/mapo.app'          # still running
/usr/bin/log show --last 1m --style compact --predicate 'subsystem == "com.maxparker72.mapo"' \
  | grep -E 'Writable Directory|Renderer|^.* E\(|^.* C\('
ls ~/Library/Logs/DiagnosticReports | grep -i mapo   # no new crash report
```

Use `/usr/bin/log`: in zsh, plain `log` is a shell builtin. Expect the writable directory to be
`~/Library/Application Support/com.maxparker72.mapo/` (or the user's override) and a Metal renderer line.
Leave the app running for the user.

## 7. Finish

- `git push origin macos-experiment` (the version commit), and tag it: `git tag mapo-<version>-<build> && git push origin mapo-<version>-<build>`.
- Tell the user: the version installed, what changed since the last tag (`git log --oneline <last tag>..HEAD -- macos`),
  the smoke-test result, and the rollback command. Ask them to try the acceptance checks of anything that
  changed (SPEC.md) and report problems with `/macos-triage`.
