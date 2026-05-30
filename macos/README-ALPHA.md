# BDSM 0.1.0-alpha1 — Tester Notes

Thanks for trying this out. A few things to know before you double-click.

## Running it

This build is not signed with an Apple Developer certificate, so macOS will
block it on first launch. You only need to do this dance once.

1. Unzip and drag **BDSM.app** into `/Applications` (or wherever you keep apps).
2. **Right-click** the app icon → **Open**.
3. macOS will show a warning ("from an unidentified developer"). Click **Open**.

If you instead see *"BDSM is damaged and can't be opened"*, that's macOS's
quarantine flag. Open Terminal and run:

```sh
xattr -dr com.apple.quarantine /Applications/BDSM.app
```

Then try step 2 again.

## What works

- Browse the world map (offline — no internet needed)
- Search for places by name or category
- Save bookmarks; organize into categories
- Import / export KML, KMZ, GPX
- Plan walking, cycling, and driving routes (preview only — no turn-by-turn)
- Record GPS tracks (if you grant location permission)
- Download additional country MWMs via **File → Download Maps…**

## What doesn't (yet)

- Real-time turn-by-turn navigation (use iOS Organic Maps for that)
- iCloud sync / cross-device sync of bookmarks
- Auto-update of the app itself

## Where your data lives

Bookmarks, downloaded country maps, and settings are stored at:

```
~/Library/Application Support/OMapsData/
```

You can move this directory via **Settings → Storage → Choose folder…** if
you want to keep it on an external drive.

## Reporting issues

When something goes wrong, please grab a screenshot and note:
- macOS version (`Apple menu → About This Mac`)
- Mac model (Apple Silicon or Intel)
- What you did right before it broke

## Credits

Built by Maxwell Parker. Based on [Organic Maps](https://organicmaps.app),
licensed under Apache 2.0. Map data © OpenStreetMap contributors (ODbL).
