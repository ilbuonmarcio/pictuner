# Proposed technical design

Status: implemented foundation with provisional choices noted below. Product requirements live in [SPEC.md](SPEC.md); implementation limits and verification live in [DEVELOPMENT.md](DEVELOPMENT.md).

The public app name, bundle display name, executable, and built `.app` are **PicTuner**. Keep `com.goldmarksolutions.pictuner`, `.pictuner`, and the existing Application Support/Pictuner folder stable to preserve app identity and saved data; the internal Swift module remains `Pictuner`.

## Native foundation

Target macOS 26.6.2 or later, as required by the user based on this Mac's installed version. Validate deployment-target support in the installed toolchain during project setup.

Use Swift and SwiftUI for the app shell, with AppKit integration where needed for keyboard routing, file access, and image interaction. Evaluate Core Image and its RAW facilities for development, effects, and GPU rendering before finalizing the pipeline. Validate against the selected deployment target and representative camera files.

The current project is a Swift Package executable bundled as a local `.app` by `scripts/build-app.sh`. It uses Swift 5 language mode with the installed Swift 6 toolchain. Core Image RAW development has been validated with a Nikon D3S sample. The first app is not sandboxed and uses local workspace paths; distribution/signing and security-scoped bookmarks remain open.

Keep these responsibilities separate:

- Workspace catalog: registered roots, access permissions, folder enumeration, stable ordering.
- Workspace store: versioned metadata, migrations, atomic autosave, recovery and save status.
- Image loader: orientation-aware decode, RAW baseline development, image identity and source-change detection.
- Adjustment model: serializable settings with explicit neutral defaults.
- Renderer: common effect graph for preview and full-resolution export.
- Preview coordinator: cancellation, caching, active-image tracking and comparison state.
- Histogram service: RGB/luminance analysis of the current rendered state.
- Export coordinator: immutable job snapshots, destination validation, rendering, progress and errors.

## Editor layout

The 215-point-wide Workspaces sidebar is conditional layout content controlled by the shared `workspaceSidebarVisible` AppStorage preference (default visible). The toolbar button and View menu/⌃⌘S shortcut use the same preference. Removing the sidebar and divider gives their width to the preview without reopening the workspace or replacing the editor model; canvas resize handling refines Fit/detail rendering and constrains the existing viewport normally.

`InspectorView` is 720 points wide, with a histogram/channel/clipping header, two always-visible columns, and a presets/reset footer. Four bordered cards use tinted icon/title header bands to separate controls: Light and Effects occupy the left column; Color and Selective Color occupy the right. Light contains tone and Detail controls; Color includes Vibrance and Color Grading. Effects starts with Black & White and Sepia sliders, followed by Vignette, Glow, and Film Grain with internal dividers; there are no built-in look buttons. Compact rows keep all 36 sliders and their values/reset buttons visible on one line each. `ContentView` supplies the available inspector height through a geometry reader: the histogram plot uses 168 points at heights of 1000 or more, and 112 points below that threshold. There is no section-selection state, conditional selective-slider hiding, or scroll container. Disabling selective color clears its transient picker/mask state while keeping its parameters visible and editable. Existing bindings and slider gesture callbacks continue to drive live rendering and undo grouping. `ResetValueButton` writes a model-derived default through the same control binding and disables itself when already at that value. Per-image resets therefore use the usual undo/autosave/render path; sampled-color reset updates its three HSV components atomically. View/export defaults and crop-draft resets stay in their existing state domains.

The `compositionGridVisible` AppStorage preference (default false) is shared by the photo toolbar’s grid button and `ContentView`, which passes it to `PhotoCanvas`. The canvas draws two lines in each direction at image-relative thirds after the overview/detail/clipping layers, with dark-under-white strokes clipped to both image and canvas. Zoom/pan and original comparison use the same image rectangle; this view-only overlay never enters the renderer or metadata. Crop mode continues to use its existing crop-relative thirds grid instead.

`PhotoToolbar` sits between the preview and filmstrip. It owns transform actions, Favorite/Reject/export marking, and a Photo actions menu with copy/paste plus contextual batch actions. During crop mode, the same bar presents aspect with its own Reset, Reset Crop, Cancel and Apply. Layout checks bound the entire inspector's fitting height to 900 points with the 112-point plot and to 1000 points with the 168-point plot, at 720 points wide with selective color both enabled and disabled, and both toolbar states to 400 points wide. The root content minimum is 1340 × 900 to accommodate both columns alongside the photo and Workspaces; the window fills the current display's available frame on every launch. `OpeningWindowSize` attaches to the scene content and applies `NSScreen.visibleFrame` on the next main-queue turn after window attachment, overriding restored dimensions while respecting the menu bar/Dock. It sizes each window once, so normal user resizing and subsequent view updates remain unaffected. The 1480 × 900 SwiftUI default is only a fallback before the opening frame is applied.

`AppModel.distractionFree` is transient scene state, independent of the sidebar AppStorage preference. `ContentView` removes the surrounding editor views while retaining the native window toolbar and the same model/viewport. ⇧⌘F and Escape restore the editor; crop mode restores the chrome and prevents hiding its draft controls.

`AppModel.comparisonWipe` and its normalized visible-region position are transient. The canvas draws edited overview/detail first, then clips original overview/detail (and matching clipping overlays) to the left of the divider. Labels/handle/grid are drawn afterward and all branches clip to canvas bounds. The divider's position is relative to the image's intersection with the viewport, so zoom/pan cannot strand it offscreen. Handle dragging changes view state only; drags elsewhere retain panning. Option-arrow/View menu actions provide keyboard access. Original comparison, mask, picker, and crop select the same image/detail branches as before; a held original or mask/picker suspends the wipe without changing its position. Histogram statistics remain full-frame rather than describing a composite screenshot.

## Rendering contract

Define one versioned, deterministic adjustment order. A starting proposal is:

1. Decode, orientation, RAW baseline and input color management.
2. Quarter-turn rotation, mirroring, fine-angle straightening with automatic edge trimming, and source-pixel crop.
3. Optional noise reduction.
4. White balance, exposure, brightness, contrast, highlights and shadows.
5. Global hue, saturation, and vibrance.
6. Clarity (midtone local contrast) and Texture (finer local contrast).
7. Selective color.
8. Black and white/sepia treatment, then shadow/highlight color grading.
9. Source-pixel sharpening, proportional-radius bloom, and vignette.
10. Deterministic monochrome grain, then output color conversion.

Validate this order visually before freezing it. Document interactions such as a monochrome preset removing color retained by selective color. Use resolution-independent effect parameters so vignette and other spatial effects scale consistently.

The original branch stops before user color/tone/effect adjustments but retains baseline RAW development, camera orientation, user crop/rotation/mirroring and necessary display conversion. Preview may reduce resolution; export must evaluate the same graph from full-resolution source data. Histogram and mask analysis use documented working spaces rather than display screenshots.

Selective-color sampling should use the input to the selective-color stage, with a clearly defined coordinate transform from displayed image to source. Persist the sampled color and its color-space interpretation. Use circular hue distance and smooth weights for hue, saturation and brightness. Disabling the effect must be an identity operation.

The implementation evaluates selective-color HSV in gamma-encoded sRGB. Temperature and tint are offsets around a 6500 K neutral in the common post-development pipeline. Selected brightness is an exposure offset in stops. Preview uses a maximum 1,800-pixel long edge when settled and 1,000 pixels during a slider drag; spatial parameters use proportions rather than fixed pixels. Current runtime kernels are deprecated; migrating them to packaged Metal kernels remains a release task.

`PhotoEffects` owns the local-contrast, grading, and grain kernels; native Core Image filters supply vibrance, denoise, sharpening, and bloom. Neutral strengths bypass their stages. Clarity and Texture use luminance differences against Gaussian baselines at 1.2% and 0.15% of the final image’s shorter dimension; Clarity weights midtones. Grading blends hue chroma separately into shadows/highlights, with a balance-controlled tonal transition and reduced influence at pure black/white. Sharpen/grain radii are specified in source pixels. Grain uses smooth deterministic coordinate noise, anchored to the cropped/oriented source, with reduced amplitude below its pixel scale; it is not regenerated randomly per frame.

Zoom baselines include a source halo for the chained neighborhood effects. Radius/halo geometry is shared with the full rendering, and all images (original, edited, sampling, mask, clipping) are cropped back to the requested visible region. Cache identity includes the halo and scale. The padded baseline remains bounded by the existing 4,096/1,000-pixel settled/interactive limits; unusually large effect contexts can reduce the detail refinement scale rather than allocating unbounded buffers. Histogram statistics still cover the whole edited image. Preview evaluates the same ordered graph at its working resolution; fine sharpening, grain, and noise differences should be inspected at 100%.

`PhotoViewport` represents physical-display-pixels per source pixel, plus a normalized bottom-left image center. The canvas converts this to points using its window's backing scale, anchors gestures at the pointer, and reports its visible source region. Fit follows window size; 100% is native display-pixel inspection rather than a multiple of Fit. Viewport state is transient and resets per photo.

When the overview cannot resolve the displayed detail, `PreviewRequest` includes a `DetailViewport`. The renderer develops/crops that visible source region, materializes a half-float baseline, and renders original/edited/sampling/mask/clipping images together with the overview frame. It retains one detail baseline and caps its output at a 4,096-pixel long edge when settled, 1,000 during slider gestures. Scaling is capped at native source resolution; greater magnification enlarges the native pixels. Vignette rendering receives the full scaled image dimensions, so crop offsets do not recenter the effect. Histogram statistics continue to describe the whole image.

The native canvas enables `clipsToBounds` explicitly (modern AppKit defaults to false) and clips its graphics context to its own bounds for every drawing branch, so zoomed image rectangles, shadows and overlays cannot cover adjacent controls. The canvas first draws the overview, then replaces the matching normalized region with the detailed rendering. Original comparison and mask/clipping controls select the corresponding detail image without changing viewport geometry. Eyedropper sampling uses the high-resolution sampling crop when the clicked point is inside it. Panning/zooming share the existing coalescing render scheduler, and image/workspace switches invalidate pending detail frames too.

## Metadata contract

The workspace root contains `.pictuner/workspace.json`. Proposed structure:

```json
{
  "schemaVersion": 5,
  "renderVersion": 3,
  "workspaceID": "UUID",
  "images": {
    "shoot/car.raw": {
      "favorite": false,
      "rejected": false,
      "exportReady": false,
      "adjustments": {}
    }
  },
  "viewState": {}
}
```

This illustrates structure, not a finalized settings schema. Define typed adjustment fields, neutral defaults, effect enablement, ranges and selective-color parameters before implementation. Use stable workspace/image identities as needed; relative paths alone do not solve external renames.

Metadata schema 2 adds `exportReady`. The store explicitly migrates schema 1–4 to schema 5/render version 3 in memory; missing flags default to false while existing adjustments/favorites/rejections are preserved. The upgraded version is persisted on the next normal save. A rejected entry is normalized to unmarked on decode. Export jobs are assembled only from marked, non-rejected entries; optional scopes can narrow this set but cannot widen it to unmarked photos.

Schema 3 adds `adjustments.geometry`: clockwise `quarterTurns`, two mirror flags, and an optional normalized bottom-left `crop` rectangle in the rotated/mirrored coordinate system. Older adjustments and presets decode with neutral geometry. Invalid crop bounds reject metadata decoding, preserving the existing file. Geometry edits use the existing adjustment undo records and autosave. Reusable color presets/copy/batch operations preserve each destination's geometry.

Schema 4/render version 2 adds the 15 effect parameters with neutral missing-key defaults. Existing color edits, geometry, flags, identities, and missing-file entries are retained; migration writes only on the normal save path. Older app versions reject this metadata instead of silently dropping effect fields. Out-of-range new parameters reject decoding and preserve the file. Reusable presets decode missing effect parameters to the same defaults.

`Renderer.render` applies geometry before color/effects. Preview applies the same source-pixel crop before downsampling and invalidates its bounded baselines when geometry changes. Detail regions use the resulting cropped image coordinate system; vignette is relative to that final frame. Interactive crop mode submits an uncropped adjustment snapshot while keeping the draft only in memory. Apply commits one adjustment; cancel/navigation discards it. Geometry transitions invalidate pending frames and reset Fit to prevent stale dimensions or sampling coordinates.

Schema 5/render version 3 adds `geometry.straightenAngle` (clockwise degrees, −15…+15). Old geometry decodes to zero; invalid angles reject metadata without rewriting it. After quarter-turn/mirror orientation, the renderer rotates about the source center and trims an original-aspect rectangle wholly inside the rotated source. Its scale is the smaller of `w/(w*cos(a)+h*sin(a))` and `h/(w*sin(a)+h*cos(a))`, using the absolute angle, with dimensions rounded down at source resolution. The usual normalized user crop follows this trimmed frame. Mirroring negates the fine angle so flipping an already straightened/cropped image preserves its visible composition; quarter-turns retain the angle.

Crop mode owns `straightenDraft`, a temporary interactive-resolution flag, and a horizon-guide mode alongside `cropDraft`. Preview requests substitute the draft angle and omit the crop while settings/metadata remain unchanged. Each completed angle frame can publish during a drag through the existing coalescing scheduler; angle changes never invalidate every in-flight frame. Release refines at 1800 pixels. Apply combines crop/angle in one adjustment; Cancel/navigation invalidate outstanding frames and discard both. The guide measures its line in bottom-left canvas points, normalizes direction to ±90°, and adds the clockwise correction to the current draft (clamped to ±15°). It ignores tiny drags and avoids sampling an unfinished frame.

Serialize writes through one store. Debounce slider updates, then flush on image transitions and normal termination. Write a temporary file on the same volume and atomically replace the metadata file. Preserve the last valid data if decoding, migration or saving fails. Handle termination/save completion explicitly rather than relying on a best-effort background task.

The workspace context menu holds a specific reset target until an explicit destructive confirmation. `WorkspaceStore.resetImages()` replaces settings for every known relative path with `ImageSettings()` while retaining workspace identity, last image, and path keys, including missing files. It uses the same lock, conflict/version/symlink checks, and atomic save; failed saves restore the previous in-memory document. `AppModel.resetWorkspace` flushes pending edits for an active target first and publishes defaults only after a successful reset save. Success clears that workspace's current undo/redo, crop/comparison/picker state and invalidates pending preview frames before requesting the default rendering at Fit. Inactive targets use a separate store, leaving the active editor intact. Missing roots are rejected rather than recreated. Registrations and reusable presets are unchanged; loading/exporting disables reset.

Store app-wide workspace registrations, security-scoped bookmarks if needed, and reusable user presets in application support. Keep regenerable caches in the appropriate macOS cache location, keyed by source identity/change information, adjustments, and render version. Do not mix cache files into authoritative workspace metadata.

## Responsiveness and access

- Perform enumeration, decoding, histogram calculation and export away from the main thread.
- Bound caches and in-flight rendering tasks; avoid retaining full-resolution decodes for an entire workspace.
- Prioritize the active photo, then nearby filmstrip thumbnails/previews.
- `PreviewCoordinator` runs at most one frame at a time with one replaceable pending request. Start immediately, publish completed frames for the current image even when input has advanced, and then render the newest pending value. Do not debounce or continually invalidate frames during a drag.
- Invalidate the preview generation on image/workspace changes so an old image can never replace the active photo. Publishing an intermediate setting for the same image is allowed during a drag; the last frame must match the final settings and normal preview resolution.
- Deliver preview completions through the main run loop's common modes so mouse tracking does not defer them until release. Slider drag completion requests the normal-resolution refinement; it only groups undo history, not the application of settings.
- Cache the active photo's decoded/resized baselines at at most two preview resolutions, plus their original images, histograms, and clipping overlays. Materialize baselines in half-float extended sRGB so later exposure/highlight adjustments retain values above display white. Invalidate these caches when the source URL/modification date changes. Export continues to render directly from full-resolution source data.
- Keep only one visible detail crop in addition to the overview caches. Do not allocate full-source-size original, edited, mask, and clipping buffers solely to implement zoom. All detail frames must use the same adjustment snapshot as their overview.
- Restore security-scoped access correctly when required by the chosen sandbox/distribution model.
- Treat comparison as temporary UI state, separate from adjustments and undo history.

## Export recipes and output depth

`ExportRecipe` defines four fixed recipes: Web Page (JPEG 0.80), Instagram (JPEG 1.0), Full Resolution (JPEG 0.95), and Lossless (PNG 16-bit). Each sets `longEdge` to zero so export retains full rendered dimensions. Applying a recipe preserves scope, folder structure and collision policy. `ExportOptions.recipe` is derived from active encoding settings rather than a separate label that can drift out of sync. Manual format/quality/size/depth changes show Custom when no recipe matches; irrelevant JPEG quality does not change a PNG recipe. Reset restores only encoding fields. The export sheet keeps its height stable during recipe/custom transitions and uses tooltips for recipe details.

PNG bit depth defaults to eight; `PNGBitDepth.sixteen` selects `CIFormat.RGBA16` at the final `Renderer.cgImage` conversion. Preview, histogram and existing default exports continue using RGBA8. ImageIO receives the resulting 16-bit CGImage directly for PNG encoding; no intermediate 8-bit preview enters this path. PNG receives no lossy-compression-quality property. All formats continue using sRGB and omit source EXIF/GPS. No workspace metadata schema change is needed for session-only export options.

Instagram deliberately uses a full-resolution, maximum-quality sRGB JPEG without automatic resizing/cropping. The official help page could not be reliably retrieved during implementation, so no current dimension/aspect limit is asserted or encoded. Revisit only with verified platform guidance; do not promise that any recipe controls Instagram's upload processing.

## Export safety

Validate all planned destinations before rendering. Resolve path aliases/symlinks and check existing file identity where possible; string comparison alone is insufficient. Revalidate before writing to reduce races. Write each output through a temporary file and finalize safely according to the collision policy. Never replace a source, even if replace-output was selected.

Export jobs capture source references, settings, output dimensions, color policy and destination policy at creation. Bound concurrency and memory for RAW processing. Cancellation stops scheduling more work and cleans up incomplete temporary output while preserving completed exports.

The first implementation restricts output to outside registered workspaces and offers rename/skip only. It publishes a temporary output with `link(2)`, which atomically refuses an existing destination, including symbolic/hard links. It never replaces an existing file. Outputs carry sRGB and omit source EXIF/GPS.

## Verification approach

Use fixture images with known colors/tones for neutral settings, hue wraparound, mask softness, orientation and histogram behavior. Test metadata round trips, migrations, corrupted input and save failure. Exercise export collision safety including symlinks and overlapping roots. Test navigation race handling with deliberately delayed rendering.

Use representative RAW files and visual comparison to validate preview/export consistency; avoid exact pixel expectations across OS RAW decoder versions without controlling that environment. Record supported camera samples and known decoder limitations. Measure navigation latency and peak memory before setting numerical performance promises.
