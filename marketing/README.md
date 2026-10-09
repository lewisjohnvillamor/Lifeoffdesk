# Life Off Desk marketing preview

A standalone, buildless marketing website. The app's Swift sources and local model-selection edits are unaffected. Static HTML/CSS/JavaScript keeps the illustration and bounded interactions lightweight; React/Three.js are unnecessary for this illustrated first version.

## Local preview

Run `python3 -m http.server 4173 --directory marketing/dist` from the repository root, then open `http://localhost:4173`. There is no package installation or build step. `dist/` is authored source, not generated output.

## Design

Calm illustrated neighborhood, approved ivory/forest palette, native sans-serif type. Taste Skill dials: variance 6, motion 3, density 3. The existing brand guide's single light theme takes precedence over the skill's generic dark-mode default. The page includes a fictional walking demonstration, three scripted planner examples, product context, FAQ and truthful availability information. No waitlist backend, fake download link, analytics or location permission request.

The demo supports start, pause, continue, replay and reset. Reduced motion switches to explicit step advances. It pauses on tab hiding or when scrolled out of view. Coordinates and illustration are synthetic; demo progress is not distance or GPS evidence. Planner examples do not run a model and are labeled accordingly. Accessibility/route and offline claims retain the app's current evidence limitations.

## Artwork

`dist/assets/neighborhood.jpg` was generated once using the built-in image-generation tool on 2026-10-09. It is a fictional place, not cartographic data. No Plainwalk source, artwork or copy was reused. Existing canonical cat art was not modified; this version focuses on the neighborhood.

Prompt: “Use case: illustration-story. Asset type: Life Off Desk marketing website hero illustration. Generate ONE landscape 1536x1024 image. Calm hand-illustrated miniature tropical Manila neighborhood in overhead / gently axonometric view, warm ivory #F8F6EF background, muted forest #46785B and sage trees, cream low-rise houses, a small coffee shop with striped green awning, little park with curved path, tiny pedestrian sidewalks, restrained terracotta rooftops, soft pencil outlines and gouache paper texture. Beautiful generous composition, neighborhood centered with soft fading blank ivory edges. Clear winding connected walking street across lower half for eventual interactive overlay. This is fictional conceptual artwork, not a real map. No text labels, no UI, no lettering, no cats (existing canonical mascot is separate), no giant 3D toy rendering. Organic drawn illustration, quiet and inviting.”

## Hosting

Commit the `marketing/` directory to the main Git repository. Point a Vercel project at that repository, set its root directory to `marketing`, choose “Other” as the framework preset, leave the build command empty, and set the output directory to `dist`. No source credentials or environment variables are required.
