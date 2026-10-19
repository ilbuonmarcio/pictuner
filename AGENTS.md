# Implementation instructions

## References

Read `docs/SPEC.md` and `docs/ARCHITECTURE.md` before implementing features. Keep them current when agreed behavior or technical decisions change. The user's latest instructions take precedence over these documents.

## Product invariants

- Never overwrite, modify, rename, or delete source images as part of editing or export.
- Store edits as metadata and autosave them across image selection changes and app restarts.
- Support RAW images in the initial release; do not silently reduce scope to JPEG/PNG.
- Use the same ordered adjustment pipeline for preview, histogram, and export.
- Hold Space to show the original; release to restore the edited preview. Provide an equivalent press-and-hold button and a visible Original indicator.
- For RAW, original means the default RAW development before user adjustments.
- Preserve responsive navigation and prevent stale asynchronous results from replacing the currently selected image.
- Sliders must update the image during a continuous drag. Never debounce preview rendering until input stops or reject every frame because a newer slider value exists. Keep rendering off the main thread, coalesce pending input, and preserve one undo step per drag.
- Preserve existing workspace metadata when a file is missing or cannot be decoded.
- Export must reject any destination that would overwrite a source image, including path aliases and symbolic links.
- Only explicitly export-marked, non-rejected photos may enter an export job. Favorite status and thumbnail selection do not grant export approval. New and migrated images start unmarked.

## Working practices

- Build the local app with `./scripts/build-app.sh` (or `release`); run `./scripts/test.sh` for regression checks. Graphics tests require macOS graphics-service access. Set `PICTUNER_RAW_FIXTURE` to a real camera RAW file to include RAW integration coverage.

- Build a native macOS application. SwiftUI and Core Image are the proposed foundation; validate platform capabilities before committing to implementation details.
- Minimum supported macOS is 26.6.2, matching the user's Mac. Do not lower it without user direction. Do not invent a camera compatibility promise or distribution/signing requirement. Record decisions when established.
- Implement in the phases described in the spec, keeping RAW and selective color in the initial release scope.
- Use focused tests for persistence, adjustment behavior, navigation races, and export safety. Inspect the UI for layout and interaction changes.
- Do not add network services, analytics, accounts, destructive source-file actions, or advanced masking without an explicit requirement.
- Keep implementation status honest: a documented feature is not an implemented feature.
- If a requirement needs clarification, continue independent work and document the unresolved decision rather than silently changing behavior.
