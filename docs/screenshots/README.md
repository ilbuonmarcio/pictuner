# README screenshots

These are captures of PicTuner’s native editor, taken on 20 October 2026. The screenshots show the current interface with a separate, disposable photo workspace; no personal photo folders or edits are included.

| File | View |
| --- | --- |
| [editor.jpg](editor.jpg) | Workspace navigation, filmstrip, histogram, and the complete two-column inspector |
| [selective-color.jpg](selective-color.jpg) | Green paint sampled with the eyedropper, with other colors desaturated |
| [crop.jpg](crop.jpg) | Crop draft, aspect selector, Apply/Cancel controls, and rule-of-thirds overlay |

## Photo credits

The photos appear inside the editor with PicTuner adjustments applied:

- **Green Mountain Landscape** — Jasper Boer, 2015. [Wikimedia Commons file and license record](https://commons.wikimedia.org/wiki/File:Green_Mountain_Landscape_(Unsplash).jpg). Listed as [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), originally published on Unsplash before its 2017 license change.
- **Green Porsche 911** — Mathious Ier, 2024. [Wikimedia Commons file and license record](https://commons.wikimedia.org/wiki/File:Green_Porsche_911.jpg). [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

PicTuner is covered by the repository’s [MIT License](../../LICENSE). The photos shown in these screenshots retain the CC0 dedication recorded above.

## Refreshing the captures

1. Build the current app with `./scripts/build-app.sh`.
2. Use a separate capture workspace containing the credited photos, with clear folder and file names. Keep personal libraries and paths out of the frame.
3. Use a wide, full-height window so the histogram and all four adjustment panels are visible. Capture the native app window only, without other apps, open menus, dialogs, tooltips, or render-progress indicators.
4. For the overview, select the landscape and make modest tone/detail adjustments. For selective color, sample the car’s green paint with the eyedropper and set other colors’ saturation to zero. For crop, return to the landscape, start a crop, and choose an aspect ratio before capturing the uncommitted draft.
5. Save JPEG screenshots with the filenames above, review them at full size, and check the root README’s relative image links.

The initial captures used the production `ContentView` and renderer in a temporary local harness with a dedicated `AppModel` support directory and bundle identifier. Only workspace setup and app-launch state were isolated; no editor controls or rendered results were mocked. The harness and source-photo downloads live under ignored `build/Readme Capture/` and are not repository assets.
