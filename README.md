# PicTuner

A native macOS photo editor for quickly browsing folders, making persistent non-destructive edits, and exporting finished copies.

The first development version is implemented in Swift, SwiftUI, AppKit, and Core Image. It requires macOS 26.6.2 or later and an installed Xcode Swift toolchain to build. It has no third-party application dependencies.

## Build and run

```sh
./scripts/build-app.sh
open build/PicTuner.app
```

For an optimized build, run `./scripts/build-app.sh release`. The script creates an ad-hoc signed local app; distribution signing and notarization are not configured. You can also open `Package.swift` in Xcode to work on the source.

The bundled app icon uses a violet aperture on an off-white tile, using Goldmark Solutions’ palette from [goldmark.solutions](https://goldmark.solutions/css/index.css). The artwork is in `Resources/AppIcon.png`. Its native macOS icon sizes are checked in as `Resources/AppIcon.icns`; run `./scripts/build-icon.sh` to regenerate that file after changing the artwork. The original generation prompt is in `Resources/AppIcon.prompt.txt`.

Choose **Add Workspace…** and select a folder. Click the preview or a thumbnail to browse with the left/right arrows. Hold **Space** or the **Original** button to compare. Click **Include in Export** (⇧⌘G) on photos you want to export; a green checkmark identifies them in the filmstrip. You can also mark/unmark selected photos together in the inspector. Edits and export flags autosave to `.pictuner/workspace.json` under the selected folder. Export includes only marked photos and writes copies to a folder outside registered workspaces.

Adjustments preview continuously as sliders move. A smaller preview keeps dragging responsive, then refines on release; each drag is one undo step.

Use the magnifier buttons or percentage menu to zoom into source-image detail. **⌘1** shows actual pixels; **⌘0** fits the photo. You can also pinch, use a mouse wheel (or Option-scroll), and drag/two-finger scroll to pan. Double-click toggles Fit/100% around the clicked point. Zoom is preserved while comparing the original and while editing.

Use **Transform** in the inspector for 90° rotation, horizontal/vertical flip, and crop (**⌘K**). Drag the crop corners or move the rectangle, choose an aspect ratio, then **Apply** (Return) or **Cancel** (Esc). These edits are saved per photo and applied to exports. Comparison keeps the current framing; color presets and copied edits preserve each photo's framing.

## Verification

```sh
./scripts/test.sh
```

Rendering tests need access to macOS graphics services; a restricted/headless execution environment can return empty Core Image buffers. The optional real-camera integration test runs when `PICTUNER_RAW_FIXTURE` points to a supported RAW file:

```sh
PICTUNER_RAW_FIXTURE="/absolute/path/to/photo.NEF" ./scripts/test.sh
```

- [Product specification](docs/SPEC.md): behavior, scope, and acceptance criteria.
- [Technical design](docs/ARCHITECTURE.md): proposed architecture, persistence, and rendering rules.
- [Development status](docs/DEVELOPMENT.md): implemented behavior, verification, and current limitations.
- [Agent instructions](AGENTS.md): rules for future implementation work.

Start with the specification. Technical choices marked provisional may be revised with evidence; confirmed product behavior should remain intact unless the user requests a change.
