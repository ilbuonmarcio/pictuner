# Pictuner

A native macOS photo editor for quickly browsing folders, making persistent non-destructive edits, and exporting finished copies.

The first development version is implemented in Swift, SwiftUI, AppKit, and Core Image. It requires macOS 26.6.2 or later and an installed Xcode Swift toolchain to build. It has no third-party application dependencies.

## Build and run

```sh
./scripts/build-app.sh
open build/Pictuner.app
```

For an optimized build, run `./scripts/build-app.sh release`. The script creates an ad-hoc signed local app; distribution signing and notarization are not configured. You can also open `Package.swift` in Xcode to work on the source.

Choose **Add Workspace…** and select a folder. Click the preview or a thumbnail to browse with the left/right arrows. Hold **Space** or the **Show Original** button to compare. Click **Include in Export** (⇧⌘G) on photos you want to export; a green checkmark identifies them in the filmstrip. You can also mark/unmark selected photos together in the inspector. Edits and export flags autosave to `.pictuner/workspace.json` under the selected folder. Export includes only marked photos and writes copies to a folder outside registered workspaces.

Adjustments preview continuously as sliders move. A smaller preview keeps dragging responsive, then refines on release; each drag is one undo step.

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
