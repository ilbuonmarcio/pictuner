# Pictuner product specification

Status: agreed product direction; first development implementation available. See [development status](DEVELOPMENT.md) for verified behavior and remaining limitations.
Updated: 2026-10-19.

## Platform requirement

Minimum supported macOS version: **26.6.2**, matching this Mac when checked on 2026-10-19 (build 25G83). Configure and validate the deployment target against this requirement during project setup.

## Purpose

Help a single user quickly edit photos stored in local folders. The primary workflow is: open a workspace, navigate photos, inspect the histogram, adjust light and color, optionally isolate a color, compare with the original, and export copies. Editing is always non-destructive.

## Workspace and browsing

- A workspace references a folder and its nested folders; adding a workspace does not import or duplicate source images.
- The left sidebar lists saved workspaces and expandable subfolders. Remember registered workspaces across launches.
- Selecting a workspace shows its images, including nested folders. Selecting a subfolder narrows the view to that subtree.
- Use a stable, natural filename ordering with relative path as a deterministic tie-breaker. Additional sorting modes can follow later.
- The center shows a large preview with fit-to-window and zoom controls.
- A bottom filmstrip shows nearby thumbnails, selection, edited status, favorites, rejected status, and a green checkmark for photos included in export.
- Left/right arrows navigate previous/next image while the browsing surface has focus. Do not intercept typing or slider keyboard input. Stop at the first and last image rather than wrapping.
- Support selecting multiple images for batch adjustments and export while maintaining one active preview image.
- Missing, unreadable, or unsupported files show a useful error without losing saved edits or preventing navigation.

## Layout

| Area | Contents |
| --- | --- |
| Left | Workspace list and folder tree |
| Center | Main image, zoom, comparison button and state |
| Right, top | Histogram and clipping controls |
| Right, body | Adjustments, presets, selective color, effects |
| Bottom | Filmstrip and image selection/navigation |

Keep frequently used adjustments directly accessible. Save preset thumbnails in the inspector rather than crowding the filmstrip. The layout should remain usable when the window is resized.

## Image formats and RAW

- The initial release supports JPEG, PNG, and RAW files supported by the selected macOS RAW decoder.
- Validate representative real camera samples during implementation and document the tested formats, cameras, and macOS versions. Do not promise universal RAW support.
- RAW development includes exposure, white balance, highlights, and shadows. It must use the RAW data for final rendering rather than exporting an embedded JPEG preview.
- The unedited baseline is a consistent default development of the RAW image. Non-RAW baselines respect orientation and embedded color profiles.
- Source files remain untouched, including embedded metadata.

## Adjustments and presets

Initial adjustments:

- Exposure and brightness/lightness.
- Contrast, highlights, and shadows.
- White balance: temperature and tint.
- Saturation and hue.
- Configurable black and white and sepia looks.
- Configurable vignette effects, with at least strength, radius, and softness.

Distinguish numerical adjustments from presets, which store reusable settings. Provide built-in looks and the ability to save custom presets. Applying a preset changes editable settings and is undoable. Exact slider ranges and additional vignette styles will be validated against the rendering implementation.

- Provide reset and undo/redo for image edits; coalesce one slider drag into one undo action.
- Apply slider and setting changes continuously while dragging; do not wait for mouse release or a pause in input. The preview, histogram, and mask/clipping views should follow completed live frames. A smaller interactive preview is acceptable if the normal-resolution preview is restored after release; export always uses full-resolution source data.
- Copy/paste adjustments between photos and apply adjustments to selected images. These operations copy settings, not rendered pixels.
- Editing one image must not inadvertently change another image's saved state.

## Selective color

Use case: keep a bright green car prominent while reducing saturation in the rest of the scene.

1. Activate an eyedropper and sample a color from the displayed image.
2. Construct a soft selection of similar colors.
3. Adjust saturation and brightness inside the selection.
4. Reduce saturation outside the selection, from subtle muting to monochrome.

Controls:

| Control | Behavior |
| --- | --- |
| Sampled color | Shows the chosen color and allows resampling |
| Hue range | Widens or narrows the selected neighboring hues |
| Saturation tolerance | Controls inclusion of less/more saturated tones |
| Brightness tolerance | Controls inclusion of highlights and shadows |
| Transition softness | Blends the selection boundary smoothly |
| Selected saturation/brightness | Accentuates the selected tones |
| Outside saturation | Mutes colors outside the selection |
| Mask preview | Displays selected regions clearly |

Persist all parameters. Handle hue wraparound, especially red, without a discontinuity. Sample and evaluate color in a consistent image color space, independent of display zoom or monitor profile. Initial scope is one sampled color range per image. Similar colors elsewhere in the image are also affected; spatial brushes and subject masks are future work.

## Histogram

- Place the histogram at the top of the right inspector.
- Offer overlaid RGB channels and a brightness/luminance view.
- Update it as adjustments change using the same rendered state as the preview; an appropriately downsampled image is acceptable.
- Offer highlight/shadow clipping indicators on the preview.
- When showing Original, show a histogram consistent with that original view.
- Label the histogram mode and define its color-space/clipping conventions during implementation.

## Original comparison

- Press and hold Space to temporarily show the original; releasing Space restores the edited preview.
- Provide a visible press-and-hold Show Original button above the preview with the same behavior and accessible labeling.
- Display an Original indicator while comparison is active.
- Comparison does not change settings, autosave data, or undo history.
- Maintain the same image, zoom, and pan position during comparison.
- Ignore key repeat. Restore the edited view on focus loss, interrupted pointer interaction, or image changes so comparison cannot become stuck.
- Do not intercept Space while typing or when another focused control needs it.
- For RAW files, original means default RAW development before user adjustments.

## Persistence

- Autosave per-image edits, favorite/reject state, export-inclusion flags, and workspace settings to `.pictuner/workspace.json` under the workspace root.
- Use relative paths so moving a workspace folder preserves associations.
- Store a metadata format version and implement explicit migrations when needed.
- Save safely and atomically. Image changes and normal app closure must not discard pending edits.
- Keep thumbnail/preview caches separate from authoritative metadata.
- On a read-only workspace, allow browsing and report clearly that edits cannot be persisted; do not imply successful saving.
- If metadata is malformed or from an unsupported newer version, retain it and present a recoverable error; do not overwrite it with defaults.
- External file renames/moves and concurrent editors need an explicit strategy before adding automatic reconciliation. Missing entries retain their saved settings.

## Export

- Each photo has an explicit **Include in Export** flag, separate from Favorite and thumbnail selection. New photos and photos migrated from older metadata start unmarked.
- The inspector provides the toggle (⇧⌘G), the filmstrip provides a context action, and multi-selected images can be marked/unmarked together. Flags survive navigation and app restarts.
- Rejecting a photo clears its export flag. Explicitly marking a rejected photo for export clears rejection.
- Export includes only marked, non-rejected photos. Default to all such photos across the workspace, even if a subfolder is currently displayed. Optional scopes narrow these to the current folder subtree, thumbnail selection, or favorites; no scope includes unmarked photos.
- Show an exact included count in the export dialog and explain that unmarked/rejected images are excluded. When nothing qualifies, explain how to mark photos and disable starting export.
- Choose an output folder, JPEG or PNG, JPEG quality, and optional resizing.
- Optionally preserve relative source folder structure.
- Render with full-resolution source data and current saved adjustment settings.
- Never overwrite originals. Check canonical destination identities, including symlinks and overlapping source/output folders.
- For collisions among output files or existing outputs, offer an explicit skip/rename/replace-output policy; replacement can never target an original.
- Show progress, support cancellation between files, and report failures without abandoning unrelated images.
- Capture a stable settings snapshot when export starts so later edits do not unpredictably alter the batch.
- Exclude generated output and `.pictuner` content from image enumeration where relevant; do not create recursive export growth.
- The initial proposed output color space is sRGB with an embedded profile. Confirm export metadata/privacy policy before implementing metadata copying.

## Initial release phases

1. Native app foundation, workspace registration, nested browsing, RAW/JPEG/PNG decode, preview, filmstrip, and navigation.
2. Shared rendering pipeline, core adjustments, original comparison, autosave and recovery, undo/redo.
3. Histogram, clipping indicators, presets, vignette, selective color, and batch adjustment tools.
4. Safe full-resolution export, cancellation, error handling, accessibility, and performance validation.

These phases are implementation order, not permission to omit later phases from the initial release.

## Deferred features

- Bokeh/background blur; confirm the intended effect before implementation.
- Subject masks, spatial brushes, multiple selective-color ranges, and advanced retouching.
- Additional sorting modes, RAW formats beyond decoder support, and further export formats.
- Cloud sync, accounts, and collaboration.

## Acceptance criteria

- Add a folder with nested JPEG, PNG, and supported RAW samples; navigate it without modifying source files.
- Adjust a photo, navigate away and back, restart the app, and verify settings and appearance persist.
- Hold/release Space and the comparison button; confirm the correct original appears without moving the viewport or changing edits.
- Confirm slider focus and text entry do not trigger image navigation or comparison accidentally.
- Drag a slider continuously and verify multiple visibly different image frames appear before mouse-up, along with updated histogram/effect previews. Verify the final setting is rendered at normal preview resolution after release and the whole drag undoes in one step. Rapid selection must still discard frames from the previous image/workspace.
- Verify RGB/luminance histograms follow edits and original comparison, and clipping indicators respond to clipped regions.
- Isolate green on a test image, mute other colors, inspect the soft mask, and reproduce the effect after reopening. Test a red sample across the hue boundary as well.
- Copy settings and apply them to selected images without modifying unselected images.
- Mark a subset for export, navigate/reopen, and verify the flags persist. Confirm that every export scope excludes unmarked and rejected images and that the default includes marked photos in nested folders. Migrating older metadata must preserve edits without implicitly marking favorites or other photos.
- Export a mixed-format workspace at full resolution; verify consistent edits, source preservation, collision handling, progress, and cancellation.
- Simulate malformed metadata, read-only storage, missing files, and interrupted saving; verify clear errors and preservation of existing data.
- Navigate rapidly through large images; verify stale renders never replace the active photo and the UI stays interactive.

## Decisions still to establish

- App distribution/signing and supported hardware.
- Exact RAW compatibility matrix and baseline development defaults.
- Adjustment ranges, preset combination behavior, and histogram/clipping conventions.
- Export metadata preservation/privacy policy.
- External rename detection, concurrent workspace access, and any read-only persistence fallback.
- Measured responsiveness and memory targets using representative photo libraries.
