# Native macOS GUI

This fork includes a small native Swift/AppKit frontend in `macos-gui/`.

It scans `/Applications` and `~/Applications`, then classifies common desktop frameworks from their bundle signatures (Electron, Flutter, CEF, Qt, NW.js, React Native, Python, JVM, GTK, wxWidgets, or Native/Other).

The GUI is intentionally independent from the Node.js CLI: users do not need Node.js to run the macOS app.

## Build artifact

GitHub Actions workflow `.github/workflows/macos-arm64-gui.yml` builds an Apple Silicon-only app:

- target: `arm64-apple-macos13.0`
- output artifact: `BuildBy-macOS-arm64.zip`
- contains: `BuildBy.app`

The artifact is ad-hoc signed, not Developer ID notarized.
