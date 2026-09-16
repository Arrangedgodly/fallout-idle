# ASSETS.md — Asset Provenance Log
<!-- Gate rule: every file under assets/ MUST have exactly one row. No row, no ship. -->
<!-- Format per docs/ultron/research/r3-cc0-assets.md. Fonts (T8) are OFL-licensed
     downloads from the official google/fonts repository; theme textures are
     original geometry authored in-repo. T11 appends icon rows here. -->

| Path | Kind | Author | Source | License | Verified | Verifier |
|------|------|--------|--------|---------|----------|----------|
| assets/fonts/big-shoulders-stencil-display/BigShouldersStencilDisplay-SemiBold.ttf | font | The Big Shoulders Project Authors (xotypeco) | github.com/google/fonts (ofl/bigshouldersstencildisplay) | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/big-shoulders-stencil-display/BigShouldersStencilDisplay-Bold.ttf | font | The Big Shoulders Project Authors (xotypeco) | github.com/google/fonts (ofl/bigshouldersstencildisplay); static wght 700 instanced from the variable font with fonttools 4.63 | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/public-sans/PublicSans-Regular.ttf | font | The Public Sans Project Authors (USWDS) | github.com/google/fonts (ofl/publicsans); static wght 400 instanced from the variable font with fonttools 4.63 | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/public-sans/PublicSans-SemiBold.ttf | font | The Public Sans Project Authors (USWDS) | github.com/google/fonts (ofl/publicsans); static wght 600 instanced from the variable font with fonttools 4.63 | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/public-sans/PublicSans-Bold.ttf | font | The Public Sans Project Authors (USWDS) | github.com/google/fonts (ofl/publicsans); static wght 700 instanced from the variable font with fonttools 4.63 | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/courier-prime/CourierPrime-Regular.ttf | font | The Courier Prime Project Authors (quoteunquoteapps) | github.com/google/fonts (ofl/courierprime) | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/fonts/courier-prime/CourierPrime-Bold.ttf | font | The Courier Prime Project Authors (quoteunquoteapps) | github.com/google/fonts (ofl/courierprime) | OFL-1.1 (bundle: OFL.txt) | 2026-09-15 | T8 agent |
| assets/theme/panel_steel_riveted.svg | texture | Valued Resident pipeline (T8, ZCode session) | original | original | 2026-09-15 | T8 agent |
| assets/theme/vent_tile.svg | texture | Valued Resident pipeline (T8, ZCode session) | original | original | 2026-09-15 | T8 agent |
| assets/theme/dot_tile.svg | texture | Valued Resident pipeline (T8, ZCode session) | original | original | 2026-09-15 | T8 agent |
| assets/theme/toggle_off.svg | texture | Valued Resident pipeline (T8, ZCode session) | original | original | 2026-09-15 | T8 agent |
| assets/theme/toggle_on.svg | texture | Valued Resident pipeline (T8, ZCode session) | original | original | 2026-09-15 | T8 agent |
| assets/theme/slider_grabber.svg | texture | Valued Resident pipeline (T9, ZCode session) | original | original | 2026-09-15 | T9 agent |
| assets/theme/slider_grabber_lit.svg | texture | Valued Resident pipeline (T9, ZCode session) | original | original | 2026-09-15 | T9 agent |

## Dev tooling (exempt from the shipped-asset gate)

<!-- The gate rule above covers files under assets/ that ship with the game.
     Per docs/ultron/research/r2-test-framework.md ("dev tooling MAY download
     addons during setup"), editor/test addons are development dependencies,
     not shipped game assets — recorded here for provenance only. GUT is an
     editor plugin: Godot strips editor plugins from exported game builds,
     and nothing under addons/ is referenced by game scenes or code. -->

| Path | Kind | Author | Source | License | Verified | Verifier |
|------|------|--------|--------|---------|----------|----------|
| addons/gut/ (259 files incl. bundled fonts/images for its editor UI) | editor plugin (dev tooling, not shipped) | Butch Wesley | github.com/bitwes/Gut branch `godot_4_7`, head commit aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605, zip sha256 2b749ce579db1969c67c57115b99d04c1a99813898046c1d3952dcc3fea23d23 (MIT, bundled: addons/gut/LICENSE.md) | MIT | 2026-09-15 | T12 agent |

<!--
Sources (font downloads, all retrieved 2026-09-15 by the T8 agent):
[^1]: https://raw.githubusercontent.com/google/fonts/main/ofl/bigshouldersstencildisplay/ — raw.githubusercontent.com/google/fonts/main/ofl/bigshouldersstencildisplay/BigShouldersStencilDisplay%5Bwght%5D.ttf (+ OFL.txt); Copyright 2019 The Big Shoulders Project Authors (https://github.com/xotypeco/big_shoulders). SemiBold (wght 600) and Bold (wght 700) instanced locally with fontTools.varLib.instancer 4.63.0 (OFL permits modification/reserve names n/a — Reserved Font Names respected by keeping family names).
[^2]: https://raw.githubusercontent.com/google/fonts/main/ofl/publicsans/ — PublicSans%5Bwght%5D.ttf (+ OFL.txt); Copyright 2015 The Public Sans Project Authors (https://github.com/uswds/public-sans). Regular 400 / SemiBold 600 / Bold 700 instanced locally with fontTools.varLib.instancer 4.63.0.
[^3]: https://raw.githubusercontent.com/google/fonts/main/ofl/courierprime/ — CourierPrime-Regular.ttf, CourierPrime-Bold.ttf (+ OFL.txt); Copyright 2015 The Courier Prime Project Authors (https://github.com/quoteunquoteapps/CourierPrime). Static files shipped as published.
Each family's verbatim OFL.txt is bundled beside the fonts in its folder. Faces were chosen against the impeccable new-work §4 training-data defaults (none of those faces are used).
-->
