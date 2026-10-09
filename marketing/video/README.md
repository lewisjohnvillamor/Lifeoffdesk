# Life Off Desk launch video (Remotion)

A 59 s product launch video (square and 16:9) that includes the help chat running for real in the "chat bubbles + kinetic type" style, built only from Life Off Desk's own material:

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

Both run 59 s: the story (coach, route, arrival, fog map), the help chat running real offline outputs (overheat, emergency, NLEX hotline, lost-and-route), on-device AI, memories, the outdoor outro and the end card.

**Licensed media** (not committed; run `./fetch-media.sh` first). Both items are under the Mixkit Free License (checked 2026-10-09): commercial use and social media posts and ads are allowed, attribution is not required, and standalone redistribution is not allowed.
- **Music:** "Just Keep Walking" by Michael Ramir C., https://mixkit.co/free-stock-music/discover/just-keep-walking-963/
- **Footage:** "Woman finishes working on her computer" (Mixkit 42653, Mixkit Free License) and "People Walking Together" (Pexels 7971035, https://www.pexels.com/video/people-walking-together-7971035/, Pexels License: free commercial use, no attribution required).

**Still missing:** real phone footage. The app screens are simulator captures of the demo world.

## Second film: features (`FeaturesSquare`, 1080×1080, 43 s)

This film walks through the help chat:
- a Taglish engine-overheat question, with the matching card steps highlighted
- an emergency (911, then Makati Rescue, then CPR)
- "Ano ang number ng NLEX?"
- the lost-and-route conversation

It closes on the route, walk and recap screens.

**Where the chat answers come from:** `src/chat-run.json` is the output of `tools/ChatRun.swift`. That script runs the app's own offline code (`SafetyPrompt.combine`, `relevantSteps`, `HotlineDirectory`, `HelpPlaces.locationDescription`, `PlaceNameSearch.find`) against the bundled data. It uses the keyword layer only (no model), and a fixed demo location in Makati, so the video labels it as such. To regenerate it, make a SwiftPM executable that depends on `Packages/LifeOffDeskCore` with this file as `main.swift`, then run it and save the output to `src/chat-run.json`.
