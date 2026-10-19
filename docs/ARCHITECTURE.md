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

`InspectorView` keeps the histogram/clipping controls and reset footer fixed, with a session-local Light/Color/Selective/Effects selection. It lays out one adjustment group at a time without a scroll container. Switching groups changes only presentation; leaving Selective clears transient picker/mask state. Existing bindings and slider gesture callbacks continue to drive live rendering and undo grouping.

`PhotoToolbar` sits between the preview and filmstrip. It owns transform actions, Favorite/Reject/export marking, and a Photo actions menu with copy/paste plus contextual batch actions. During crop mode, the same bar presents aspect, Reset, Cancel and Apply. Layout checks bound each expanded inspector group's fitting height to 680 points at 290 points wide, and both toolbar states to 400 points wide.

## Rendering contract

Define one versioned, deterministic adjustment order. A starting proposal is:

1. Decode, orientation, RAW baseline and input color management.
2. Quarter-turn rotation, mirroring, and source-pixel crop.
3. White balance and exposure.
4. Tone adjustments: brightness, contrast, highlights and shadows.
5. Global hue and saturation.
6. Selective color.
7. Black and white/sepia treatment.
8. Vignette.
9. Output color conversion.

Validate this order visually before freezing it. Document interactions such as a monochrome preset removing color retained by selective color. Use resolution-independent effect parameters so vignette and other spatial effects scale consistently.

The original branch stops before user color/tone/effect adjustments but retains baseline RAW development, camera orientation, user crop/rotation/mirroring and necessary display conversion. Preview may reduce resolution; export must evaluate the same graph from full-resolution source data. Histogram and mask analysis use documented working spaces rather than display screenshots.

Selective-color sampling should use the input to the selective-color stage, with a clearly defined coordinate transform from displayed image to source. Persist the sampled color and its color-space interpretation. Use circular hue distance and smooth weights for hue, saturation and brightness. Disabling the effect must be an identity operation.

The implementation evaluates selective-color HSV in gamma-encoded sRGB. Temperature and tint are offsets around a 6500 K neutral in the common post-development pipeline. Selected brightness is an exposure offset in stops. Preview uses a maximum 1,800-pixel long edge when settled and 1,000 pixels during a slider drag; spatial parameters use proportions rather than fixed pixels. Current runtime kernels are deprecated; migrating them to packaged Metal kernels remains a release task.

`PhotoViewport` represents physical-display-pixels per source pixel, plus a normalized bottom-left image center. The canvas converts this to points using its window's backing scale, anchors gestures at the pointer, and reports its visible source region. Fit follows window size; 100% is native display-pixel inspection rather than a multiple of Fit. Viewport state is transient and resets per photo.

When the overview cannot resolve the displayed detail, `PreviewRequest` includes a `DetailViewport`. The renderer develops/crops that visible source region, materializes a half-float baseline, and renders original/edited/sampling/mask/clipping images together with the overview frame. It retains one detail baseline and caps its output at a 4,096-pixel long edge when settled, 1,000 during slider gestures. Scaling is capped at native source resolution; greater magnification enlarges the native pixels. Vignette rendering receives the full scaled image dimensions, so crop offsets do not recenter the effect. Histogram statistics continue to describe the whole image.

The native canvas enables `clipsToBounds` explicitly (modern AppKit defaults to false) and clips its graphics context to its own bounds for every drawing branch, so zoomed image rectangles, shadows and overlays cannot cover adjacent controls. The canvas first draws the overview, then replaces the matching normalized region with the detailed rendering. Original comparison and mask/clipping controls select the corresponding detail image without changing viewport geometry. Eyedropper sampling uses the high-resolution sampling crop when the clicked point is inside it. Panning/zooming share the existing coalescing render scheduler, and image/workspace switches invalidate pending detail frames too.

## Metadata contract

The workspace root contains `.pictuner/workspace.json`. Proposed structure:

```json
{
  "schemaVersion": 3,
  "renderVersion": 1,
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

Metadata schema 2 adds `exportReady`. The store explicitly migrates schema 1 and 2 to schema 3 in memory; missing flags default to false while existing adjustments/favorites/rejections are preserved. The upgraded version is persisted on the next normal save. A rejected entry is normalized to unmarked on decode. Export jobs are assembled only from marked, non-rejected entries; optional scopes can narrow this set but cannot widen it to unmarked photos.

Schema 3 adds `adjustments.geometry`: clockwise `quarterTurns`, two mirror flags, and an optional normalized bottom-left `crop` rectangle in the rotated/mirrored coordinate system. Older adjustments and presets decode with neutral geometry. Invalid crop bounds reject metadata decoding, preserving the existing file. Geometry edits use the existing adjustment undo records and autosave. Reusable color presets/copy/batch operations preserve each destination's geometry.

`Renderer.render` applies geometry before color/effects. Preview applies the same source-pixel crop before downsampling and invalidates its bounded baselines when geometry changes. Detail regions use the resulting cropped image coordinate system; vignette is relative to that final frame. Interactive crop mode submits an uncropped adjustment snapshot while keeping the draft only in memory. Apply commits one adjustment; cancel/navigation discards it. Geometry transitions invalidate pending frames and reset Fit to prevent stale dimensions or sampling coordinates.

Serialize writes through one store. Debounce slider updates, then flush on image transitions and normal termination. Write a temporary file on the same volume and atomically replace the metadata file. Preserve the last valid data if decoding, migration or saving fails. Handle termination/save completion explicitly rather than relying on a best-effort background task.

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

## Export safety

Validate all planned destinations before rendering. Resolve path aliases/symlinks and check existing file identity where possible; string comparison alone is insufficient. Revalidate before writing to reduce races. Write each output through a temporary file and finalize safely according to the collision policy. Never replace a source, even if replace-output was selected.

Export jobs capture source references, settings, output dimensions, color policy and destination policy at creation. Bound concurrency and memory for RAW processing. Cancellation stops scheduling more work and cleans up incomplete temporary output while preserving completed exports.

The first implementation restricts output to outside registered workspaces and offers rename/skip only. It publishes a temporary output with `link(2)`, which atomically refuses an existing destination, including symbolic/hard links. It never replaces an existing file. Outputs carry sRGB and omit source EXIF/GPS.

## Verification approach

Use fixture images with known colors/tones for neutral settings, hue wraparound, mask softness, orientation and histogram behavior. Test metadata round trips, migrations, corrupted input and save failure. Exercise export collision safety including symlinks and overlapping roots. Test navigation race handling with deliberately delayed rendering.

Use representative RAW files and visual comparison to validate preview/export consistency; avoid exact pixel expectations across OS RAW decoder versions without controlling that environment. Record supported camera samples and known decoder limitations. Measure navigation latency and peak memory before setting numerical performance promises.
