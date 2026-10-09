# Life Off Desk launch video (Remotion)

A ~56 s product launch video (square and 16:9) in the "chat bubbles + kinetic type" style, built only from Life Off Desk's own material:

- **Screens:** unedited captures of the app's labelled demo world (`ci-screenshots` branch, `--marketing` flag).
- **Copy:** real app strings (the coach line, arrival card, help-chat questions and card titles).
- **Brand:** the mascot, plus colours from `docs/BRAND-GUIDE.md`.
- **Font:** Inter (SIL OFL, from `@fontsource/inter`), bundled in `public/fonts`.

```bash
npm i
npx remotion studio                                   # preview and edit timing
npx remotion render LaunchVideo out/life-off-desk-launch.mp4
# In the cloud container, add: --browser-executable=/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell.real
```

**Scenes** (`src/scenes/`), with durations in `src/LaunchVideo.tsx`:
1. Cold open: the coach chat, the route, and "Nakarating ka na!".
2. Introducing Life Off Desk.
3. Every walk draws your map.
4. Notices when your world gets smaller.
5. Help, even with no signal.
6. Runs on your iPhone.
7. Keep the memories.
8. End card.

**Formats:**
- `LaunchSquare` (1080×1080): the cut for X and LinkedIn feeds.
- `LaunchVideo` (1920×1080): the cut for the website and YouTube.

Both run about 56 s.

**Licensed media** (not committed; run `./fetch-media.sh` first). Both items are under the Mixkit Free License (checked 2026-10-09): commercial use and social media posts and ads are allowed, attribution is not required, and standalone redistribution is not allowed.
- **Music:** "Just Keep Walking" by Michael Ramir C., https://mixkit.co/free-stock-music/discover/just-keep-walking-963/
- **Footage:** "Woman finishes working on her computer" (42653) and "Girl walking through a park on a sunny day" (4871), from https://mixkit.co/free-stock-video/

**Still missing:** real phone footage. The app screens are simulator captures of the demo world.
