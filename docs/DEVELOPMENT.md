# First development version

Updated: 2026-10-19. This is a local development app, not a signed/notarized distribution release.

## Implemented

- Registered workspace folders, recursive natural-order image enumeration, expandable subfolder navigation, and refresh/remove-reference actions.
- JPEG/PNG loading and RAW development through `CIRAWFilter`; unsupported camera files produce an error without blocking navigation.
- Dark native interface with amber accents, a large preview, fit/2×/4× zoom relative to fit, drag/scroll panning when zoomed, and a lazy thumbnail filmstrip.
- Left/right browsing when the preview has keyboard focus; image selection focuses the preview. Slider and text-field keyboard input stays with those controls.
- Exposure, brightness, contrast, highlights, shadows, temperature/tint offsets, saturation, hue, black and white, sepia, and adjustable vignette.
- Continuous slider previews with one in-flight render and one latest pending setting, common-mode delivery during mouse tracking, a 1,000-pixel interactive preview, and 1,800-pixel refinement after release. Cached half-float baselines avoid repeated RAW development while preserving highlight headroom; each drag remains one undo operation.
- One sampled selective-color range with tolerances, softness, selected-color saturation/exposure, outside saturation, and mask preview.
- RGB and luma histograms, with square-root-scaled counts for readability. Bins use rendered 8-bit sRGB values; luma uses 0.2126 R + 0.7152 G + 0.0722 B on those encoded values.
- Optional clipping overlay: red if any encoded channel reaches white, blue if any reaches black (white takes precedence). This is output-channel clipping, not a measurement of recoverable RAW sensor detail.
- Hold-Space and press-and-hold button comparison, with Original labeling and corresponding histogram. Accessibility activation of the button provides a one-second original preview.
- Favorites/reject flags, Command-click multi-selection, copy/paste adjustments, undoable batch application, built-in looks, and named user presets.
- Persistent Include in Export flags (⇧⌘G), green filmstrip checkmarks, per-photo context actions, batch mark/unmark, and a workspace-wide marked count. Rejecting a photo unmarks it; explicitly marking it clears rejection. Existing schema 1 workspaces migrate to schema 2 with their edits preserved and all images initially unmarked.
- Per-image undo/redo with slider gesture coalescing. History is session-local and resets on image selection; batch operations can be undone before leaving that image.
- Debounced atomic JSON autosave, last-image restoration, metadata version checks, preservation of malformed/newer metadata, and external-write conflict detection.
- JPEG/PNG export with full-resolution RAW rendering, quality, optional long-edge downsizing, optional subfolder preservation, cancellation, per-file errors, and rename/skip collision behavior. Only marked, non-rejected images qualify; the default covers the whole workspace and optional scopes narrow to the current folder, selection, or favorites.

## Current limitations and deliberate first-version policies

- Export destinations must be outside all registered workspaces. Existing output replacement is not offered; rename/skip avoids replacing any existing file or link.
- Exports use sRGB and do not copy source EXIF/GPS. The export dialog states this policy.
- Camera compatibility follows the host macOS RAW decoder; only the sample listed below has been validated so far. More camera samples are needed before publishing a compatibility matrix.
- The folder tree is derived from discovered image paths, so empty folders are not shown. Filesystem changes appear after Refresh; there is no live watcher or external rename matching yet.
- Workspaces are stored as local paths in Application Support. The app currently runs without App Sandbox; security-scoped bookmarks and distribution entitlements are pending the distribution decision.
- Read-only workspaces can be browsed. Save errors are visible and editing is disabled after a persistence failure; there is no fallback metadata location. Pending edits remain in memory, with retry for a transient save failure. Failed saves block switching away or quitting to avoid discarding them.
- External metadata conflicts require reloading; automatic merging is not implemented. The save-error alert offers retry or an explicit reload-and-discard action for unsaved in-memory changes. Do not use multiple editors for the same workspace.
- Presets are presented as labeled buttons/menu items; visual preset thumbnails and additional vignette styles remain polish work.
- Custom Core Image kernels currently use the deprecated runtime Core Image Kernel Language initializer. It works on the tested Mac but should migrate to packaged Metal kernels before a distribution release; the Metal compiler toolchain component is not fully available on this Mac.
- Thumbnail images show the source rather than baked edits, with edited/favorite/reject/export-inclusion badges. Preview resolution is capped at a 1,800-pixel long edge (1,000 while dragging sliders); zoom does not yet request higher-resolution preview tiles. Live frame rate depends on the image, effects, and hardware; there is no fixed FPS guarantee.
- No bokeh, spatial masks, brushes, or network services.

## Validation record

On this Mac (macOS 26.6.2, Apple Swift 6.4 toolchain, macOS 27 SDK), the native app built and launched. Interactive checks covered folder selection, nested JPEG/PNG browsing, exposure changes, selective-color sampling, histogram display, navigation restoring per-image edits, and temporary original comparison.

All 26 automated tests passed, including the optional RAW integration test. The suite covers metadata round trips, corrupt/newer metadata preservation, schema 1 migration, persistent export flags and marked-only filtering across all scopes, concurrent-write detection and explicit recovery, metadata symlink refusal, recursive natural sorting, collision/symlink/hard-link export safety, neutral rendering, exposure, selective-color isolation, hue wraparound and soft masks, histogram counts, resizing/export, rapid selection with pending renders, coalesced slider undo, batch undo, and comparison key release/focus loss. Live-preview regression tests verify repeated changing image frames before gesture release, final-resolution refinement, coalescing while a slow frame runs, stale-workspace frame rejection, delivery in the mouse-tracking run-loop mode, and highlight headroom in cached previews.

The optional RAW integration test was run with a **Nikon D3S NEF**, `iss030e122639.NEF`, from the [rawpy test fixtures](https://github.com/letmaik/rawpy/tree/main/test). It verified actual RAW development, preview generation, full-resolution JPEG export, and unchanged source bytes. The downloaded fixture is an ignored local testing artifact, not part of the repository.

## Remaining release validation

Test additional camera formats and large libraries, tune responsiveness/memory targets, verify access failures on removable/network volumes, exercise VoiceOver and reduced motion, and validate output color profiles in other applications. Source-preservation and metadata-recovery tests must continue to pass as the app evolves.
