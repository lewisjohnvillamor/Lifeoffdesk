# Life Off Desk launch video (Remotion)

A ~47 s, 1920×1080 product launch video in the "chat bubbles + kinetic type" style, built only from Life Off Desk's own material:

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

**Not included yet:**
- **Music:** add a licensed track with `<Audio>` from `@remotion/media`.
- **Real phone footage:** the screens are simulator captures of the demo world.
