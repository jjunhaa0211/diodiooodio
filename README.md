# diodiooodio

`diodiooodio` is a macOS menu bar app for per-app audio control, output routing, and media-focused utilities.

## Key Features

- Per-app volume and mute controls
- Multi-device output routing
- Input device monitoring and control
- 10-band EQ with preset support
- Pinned app controls for fast access
- Apple Music now-playing integration
- Dynamic Bar (Notch) modules for music, files, and time
- URL scheme hooks for automation

## Install

Download the latest build from [Releases](https://github.com/jjunhaa0211/diodiooodio/releases) and drag `diodiooodio.app` into `/Applications`.

Releases built without Apple signing secrets are ad-hoc signed rather than notarized, so macOS quarantines them on download and refuses to open the app. Clear the quarantine attribute once after installing:

```bash
xattr -dr com.apple.quarantine /Applications/diodiooodio.app
```

The app is a menu bar app (`LSUIElement`), so it shows up in the menu bar with no Dock icon or main window.

Ad-hoc signed builds also get a new code signature on every release, which means macOS drops the Automation and notification permissions each time you update. Re-grant them in **System Settings → Privacy & Security** after updating.

## Attribution

This repository contains derivative work based on the original **FineTune** project by **Ronit Singh**.

- Original author: Ronit Singh
- Upstream project: [ronitsingh10/FineTune](https://github.com/ronitsingh10/FineTune)
- Current repository: [jjunhaa0211/diodiooodio](https://github.com/jjunhaa0211/diodiooodio)
- Additional attribution details: [NOTICE](NOTICE)

## License and Compliance

This project is distributed under the **GNU General Public License v3.0 (GPL-3.0)**, consistent with the upstream FineTune license.

If you redistribute this project (source or binaries), keep:

1. The GPL-3.0 license text
2. Appropriate attribution/copyright notices
3. Access to corresponding source code as required by GPL-3.0

See [LICENSE](LICENSE) for the full license terms.

## Build From Source

```bash
git clone https://github.com/jjunhaa0211/diodiooodio.git
cd diodiooodio
open diodiooodio.xcodeproj
```
