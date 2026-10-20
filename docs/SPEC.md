# PicTuner product specification

Status: agreed product direction; first development implementation available. See [development status](DEVELOPMENT.md) for verified behavior and remaining limitations.
Updated: 2026-10-20.

The app name is **PicTuner** (capital T).

## Platform requirement

Minimum supported macOS version: **26.6.2**, matching this Mac when checked on 2026-10-19 (build 25G83). Configure and validate the deployment target against this requirement during project setup.

## Purpose

Help a single user quickly edit photos stored in local folders. The primary workflow is: open a workspace, navigate photos, inspect the histogram, adjust light and color, optionally isolate a color, compare with the original, and export copies. Editing is always non-destructive.

## Workspace and browsing

- A workspace references a folder and its nested folders; adding a workspace does not import or duplicate source images.
- The left sidebar lists saved workspaces and expandable subfolders. Remember registered workspaces across launches.
- Toggle Workspaces using the toolbar sidebar button or View → Hide/Show Workspaces (⌃⌘S). Remember visibility across launches. Hiding it expands the photo area and moves the filmstrip from below the preview to the bottom of the right inspector, reclaiming preview height for portrait photos. Showing Workspaces moves the filmstrip back. Preserve the selected workspace, folder, photo, edits, and zoom mode, and scroll the relocated picker to the active photo.
- Selecting a workspace shows its images, including nested folders. Selecting a subfolder narrows the view to that subtree.
- Use a stable, natural filename ordering with relative path as a deterministic tie-breaker. Additional sorting modes can follow later.
- The center shows a large preview with fit-to-window and zoom controls.
- Zoom includes Fit, 100% actual pixels, percentage presets through 800%, and zoom-in/out buttons. At 100%, one source pixel maps to one physical display pixel, accounting for Retina scale. Support pinch-to-zoom, mouse-wheel zoom, Option-scroll zoom, drag/two-finger pan, and double-click to toggle Fit/100% around the clicked image point. Keyboard shortcuts are ⌘0 (Fit), ⌘1 (100%), ⌘+ and ⌘−.
- A grid button beside the photo transform controls toggles a 3×3 (rule-of-thirds) composition grid over the image. Default off; remember visibility across launches and photo/workspace changes. Align it to the image through zoom, pan, rotation, crop, and original comparison; keep it inside the photo/preview bounds. It is a display overlay and does not enter edits, history, histogram, presets, or export. During crop mode, retain the existing crop-relative grid and contextual controls.
- Keep the image, shadows, and all overlays clipped to the preview area at every zoom/pan position; the toolbar, sidebar, inspector, and filmstrip must remain visible.
- Zoomed views render additional detail from the source image for the visible region rather than magnifying only the reduced preview. Keep the region under the pointer steady while zooming, constrain panning to the image, and retain the viewport during edits/comparison. Selecting another photo resets to Fit.
- A bottom filmstrip shows nearby thumbnails, selection, edited status, favorites, rejected status, and a green checkmark for photos included in export.
- Left/right arrows navigate previous/next image while the browsing surface has focus. Do not intercept typing or slider keyboard input. Stop at the first and last image rather than wrapping.
- Support selecting multiple images for batch adjustments and export while maintaining one active preview image.
- Missing, unreadable, or unsupported files show a useful error without losing saved edits or preventing navigation.
- The workspace folder's context menu offers **Reset Workspace…**. Require confirmation naming the workspace and explaining that all photo adjustments (including crop/rotation/mirroring), favorites, rejections, and export marks in the entire workspace/subfolders will be cleared. Keep source files, the workspace registration, saved presets, and current folder/photo selection. Reset is not undoable; clear existing edit history after success. Preserve metadata path associations for missing/unreadable photos, resetting their settings too. Do not reset during loading/export or bypass metadata errors/conflict checks.

## Layout

On every launch, fill the current display’s available width and height, respecting the menu bar and Dock. Override the previously saved window size at opening; keep normal window controls and allow resizing afterward.

| Area | Contents |
| --- | --- |
| Left | Workspace list and folder tree |
| Center | Main image, zoom, comparison button and state |
| Right, top | Histogram and clipping controls |
| Right, body | Four always-visible bordered panels in two columns: Light/Effects on the left, Color/Selective Color on the right |
| Below preview | Crop/rotate/flip, Favorite/Reject/export marking, and Photo actions menu; contextual crop controls while cropping |
| Bottom | Filmstrip below the preview with Workspaces visible, or below the right inspector with Workspaces hidden |

Keep the histogram, channel selector, and clipping toggle above a 720-point-wide, two-column inspector. Give Light, Color, Selective Color, and Effects distinct bordered cards with contrasting header bands and icons. Light also contains Detail controls; Color contains Color Grading. Effects groups Looks, Vignette, Glow, and Film Grain. Slider rows show their label, slider, value, and Reset together on one line. The histogram plot is 168 points tall (three times the previous height) when the inspector has at least 1000 points of height, and 112 points (twice the previous height) in shorter windows. Show all 36 adjustment sliders, selective-color enable/picker/mask controls, looks, vignette, and per-control resets at once, with no adjustment tabs, collapsed groups, or inspector scrolling. Selective sliders stay visible and editable when the effect is disabled; its enable checkbox controls whether those settings affect the image, and the mask toggle is disabled while the effect is off. Keep presets, Save Preset, and Reset All Edits in the bottom bar. The minimum content size is 1340 × 900, retaining a usable photo area with Workspaces visible. When the filmstrip is docked on the right and space is tight, reduce panel padding and row gaps while retaining slider heights, labels, values, resets, all four panels and the histogram. No vertical inspector scrolling or hidden controls. Base histogram height on the whole right column so docking alone does not shrink it.

Copy/paste and multi-selection actions live in the Photo actions menu below the preview, regardless of filmstrip placement. Batch actions only appear for multiple selections. Crop mode replaces that bar with aspect, Reset, Cancel and Apply controls beside the image.

Keep frequently used adjustments directly accessible. Save preset thumbnails in the inspector rather than crowding the filmstrip. The layout should remain usable when the window is resized.

Use concise native-app labels. Avoid marketing slogans, demo copy, repeated explanations, and persistent tutorials. Surface guidance in relevant empty/error states or tooltips. Show save failures and export progress; keep routine autosave quiet. Show batch actions only for multi-selection.

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

Additional adjustments:

- Vibrance (−1…1) complements Saturation.
- Clarity and Texture (−1…1): broad midtone contrast and finer surface detail; negative values soften.
- Sharpening amount (0…2) and source-pixel radius (0.3…5 px), plus Noise Reduction (0…1).
- Glow strength (0…1) and radius (0.002…0.06 of the image’s shorter dimension).
- Color Grading: separate shadow/highlight hue (0…360°) and tint strength (0…1), with tonal balance (−1…1). Tint strengths default to zero.
- Film Grain strength (0…1) and source-pixel size (0.5…8 px). Use a fixed, image-aligned pattern so redraws and panning do not randomize grain.

All new amounts default to neutral, persist per photo, and participate in live preview, histogram, original comparison, undo/reset, presets, copy/batch operations, and export. Spatial effects use source-aligned radii and context outside zoom crops so their edges do not develop seams. The original comparison bypasses all these effects while retaining geometry.

Distinguish numerical adjustments from presets, which store reusable settings. Keep Black & White and Sepia as sliders and provide the ability to save custom presets. Do not show Natural, Mono, or Sepia preset buttons. Applying a preset changes editable settings and is undoable. Exact slider ranges and additional vignette styles will be validated against the rendering implementation.

- Provide reset and undo/redo for image edits; coalesce one slider drag into one undo action.
- Put a small Reset beside every adjustment slider and the sampled-color selector. Reset only that control to its model default, preserving other edits; each image-setting reset is one undoable, autosaved action. Disable Reset when already at the default.
- Also provide individual Reset buttons for histogram channels (RGB), zoom (Fit), crop aspect (Free), and export settings. These restore only that selector/option; display/export choices do not enter photo-edit undo history, and crop aspect stays a draft until Apply.
- Apply slider and setting changes continuously while dragging; do not wait for mouse release or a pause in input. The preview, histogram, and mask/clipping views should follow completed live frames. A smaller interactive preview is acceptable if the normal-resolution preview is restored after release; export always uses full-resolution source data.
- Copy/paste adjustments between photos and apply adjustments to selected images. These operations copy settings, not rendered pixels.
- Editing one image must not inadvertently change another image's saved state.

## Crop, straighten, rotate, and mirror

- Straighten is available beside Crop and in the Photo menu. It opens the crop editor with a horizon guide; the crop editor always provides a −15°…+15° angle slider, value, Reset, and Draw Horizon button in a separate contextual row beside the preview.
- Drag along a horizon to level it, or adjust the angle continuously. Positive angles rotate clockwise. Guide direction does not matter; ignore drags shorter than 12 points and clamp corrections to the supported range.
- Straightening runs after quarter-turn/mirror orientation, before user crop. Automatically trim a centered frame with the oriented source's aspect ratio so rotated corners do not create empty wedges. Crop coordinates refer to this trimmed frame. Comparison retains the same geometry.
- Crop and angle remain a draft until Apply/Return; commit them as one undo action. Cancel/Escape or image navigation discards both. Exclude straightening from reusable color presets and copy/batch edits, like other framing.

- Provide 90° clockwise/counterclockwise rotation and horizontal/vertical flip in the photo toolbar above the filmstrip and the Photo menu.
- Crop (⌘K) shows the full rotated/mirrored image at Fit, with a draggable rectangle, corner handles, rule-of-thirds grid, and dimmed excluded area. Drag inside to move the selection, or outside it to draw a new rectangle.
- Offer Free, Original, 1:1, 4:3, 3:2, 16:9, 3:4, 2:3, and 9:16 aspect ratios. Original means the full image's current rotated aspect ratio.
- Apply/Return commits one undoable crop; Cancel/Escape discards the draft. Arrow keys move the crop by one source pixel, Shift-arrow by ten. Reset Crop restores the largest crop for the selected aspect. Remove Crop restores the full frame without changing color edits, rotation, or mirror settings.
- Geometry changes reset the viewport to Fit. Rotating/flipping a cropped image transforms the existing selection along with it. Navigating away cancels an uncommitted crop; export waits until Apply or Cancel.
- Persist normalized crop coordinates after rotation/mirroring. Round crop boundaries once at source resolution; preview, detail rendering, histogram, sampling, and export use that same image geometry.
- Presets, copy/paste, and batch color edits preserve each destination photo's own framing. The main Reset action resets all edits, including geometry.

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
- Provide a visible press-and-hold Original button above the preview with the same behavior and accessible labeling. Put the hold/Space instruction in its tooltip rather than its title.
- Display an Original indicator while comparison is active.
- Comparison does not change settings, autosave data, or undo history.
- Maintain the same image, crop, rotation, mirror, zoom, and pan position during comparison. Original comparison temporarily bypasses color/tone/effect adjustments; Remove Crop restores the full frame.
- Ignore key repeat. Restore the edited view on focus loss, interrupted pointer interaction, or image changes so comparison cannot become stuck.
- Do not intercept Space while typing or when another focused control needs it.
- For RAW files, original means default RAW development before user color/tone/effect adjustments, with the current framing retained.

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
- The photo toolbar provides the checkmark toggle (⇧⌘G), the filmstrip provides a context action, and multi-selected images can be marked/unmarked together through Photo actions. Flags survive navigation and app restarts.
- Rejecting a photo clears its export flag. Explicitly marking a rejected photo for export clears rejection.
- Export includes only marked, non-rejected photos. Default to all such photos across the workspace, even if a subfolder is currently displayed. Optional scopes narrow these to the current folder subtree, thumbnail selection, or favorites; no scope includes unmarked photos.
- Show an exact included count in the export dialog and label scopes as marked photos. When nothing qualifies, show the marking instruction and disable starting export. Keep color-profile/metadata policy concise; report destination restrictions only when a chosen destination is invalid.
- Choose an output folder, JPEG or PNG, JPEG quality, and optional resizing.
- Provide four built-in export recipes in the export dialog: **Web Page** (full-resolution JPEG, 80% quality), **Instagram** (full-resolution JPEG, 100%), **Full Resolution** (full-resolution JPEG, 95%), and **Lossless** (full-resolution 16-bit PNG). All keep the current photo crop/orientation, sRGB, and the existing metadata-exclusion policy; none resizes, crops, or upscales automatically.
- Instagram is a maximum-quality input recipe, not a promise about platform output or a fixed platform dimension/aspect policy. Upload processing is controlled by Instagram. Do not force an unverified size limit or recrop a photo as part of this recipe.
- Recipes change format, JPEG quality, size, and PNG bit depth only. Keep export scope, explicit approval flags, folder structure and collision choices. All controls remain editable; show Custom when encoding settings do not match a recipe. Recipe Reset restores the existing encoding defaults (JPEG 90%, full resolution, 8-bit PNG setting), retaining job-selection/file-handling choices.
- PNG export offers 8-bit and 16-bit output. Lossless refers to compression of the rendered sRGB image, not preservation of a RAW sensor file or all source metadata. Recipes are fixed built-ins, always available; export choices remain session state and survive reopening the dialog within the session.
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

- At minimum window size, confirm every adjustment slider and selector is visible together, with selective color both enabled and disabled, without inspector scrolling or section switching. Verify crop controls and photo actions fit the narrowest preview.

- Add a folder with nested JPEG, PNG, and supported RAW samples; navigate it without modifying source files.
- Adjust a photo, navigate away and back, restart the app, and verify settings and appearance persist.
- Hold/release Space and the comparison button; confirm the correct original appears without moving the viewport or changing edits.
- Inspect a high-frequency test image at 100% on a Retina display and verify source pixels resolve beyond the overview's detail. Verify anchored zoom, bounded panning, Fit reset, higher-resolution original/mask/clipping views, and unchanged photo metadata when zooming. Vignette position and other image-wide effect coordinates must remain consistent in the detail region.
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

## Distraction-free viewing and before/after wipe

- A window-toolbar button and View menu item (⇧⌘F) hide the Workspaces sidebar, preview header, inspector, photo toolbar, filmstrip, and status bar. Keep the native toolbar with an explicit exit button. Escape restores the editor. Entering crop restores the editor; distraction-free mode is unavailable while cropping.
- Keep the active photo, its edits, zoom, and pan when switching modes, subject to normal viewport bounds. Fit adapts to the larger canvas. Arrow navigation, zoom shortcuts/gestures, and hold-Space comparison continue to work. Preserve the separate sidebar visibility preference. Start each launch in the normal editor.
- A toolbar button and View menu item (⌘\) toggle a vertical before/after wipe: original on the left, edited on the right, with labels and a draggable divider. Use Option–Left/Right or the corresponding View menu items to move it in 5% increments.
- Both sides share framing, zoom, pan, and matching source-detail images. Position the divider within the visible photo region so it remains reachable when zoomed or panned. Dragging away from the divider still pans normally.
- Holding Space temporarily shows the full original, then restores the wipe on release. Mask and eyedropper displays temporarily suspend the wipe; entering crop turns it off. The histogram continues to show the whole edited image unless the original is held.
- Wipe visibility/position and distraction-free mode are session-only view state and never enter metadata, undo, presets, the rendering graph, or exported images. Start with the divider centered and recenter it when selecting another photo.
