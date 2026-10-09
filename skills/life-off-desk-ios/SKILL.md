---
name: life-off-desk-ios
description: Build or review Life Off Desk native iPhone walking, fog-of-war maps, walk sessions, recaps and local persistence. Use for this project on Mac/Xcode targeting iPhone 12 Pro Max; keep both offline walking and on-device AI suggestions in the required MVP.
---

# Life Off Desk iOS

Read `references/build-contract.md` before choosing scope. Inspect current repository instructions and existing code. Honor new explicit user decisions over older defaults.

1. Prove a signed minimal launch on the real target phone; record iOS and deployment target.
2. Keep map-first entry with Start walking and a secondary planner action. Chat is optional to use, mandatory to implement.
3. Build explicit session states and real Core Location samples. Test permission denial, pause/resume, stale fixes, jumps and update gaps. Break invalid gaps rather than revealing straight connections. Tune provisional filter values on an outdoor walk.
4. Reveal a narrow accepted corridor over bundled local vector geometry. Persist exploration independently from basemap versions. Show absent coverage honestly; do not rely on online-cache luck.
5. Persist incrementally and atomically. Recover interrupted sessions paused. Finish idempotently; compute distance from accepted segments and active duration excluding pauses.
6. Integrate the separately verified local AI planner through a selected destination. Never turn model failure into walk failure. Preserve source-backed place facts and explicitly labeled straight-line distances.
7. Verify both paths in airplane mode with Wi-Fi off and Mac disconnected, plus real GPS outdoors and relaunch persistence. Record evidence and limits in project BUILD-STATUS.md.

Apply `$life-off-desk-brand` for appearance and `$life-off-desk-local-ai` for inference. Defer photos/cutouts, full Luzon detail, road routing and social features until both required paths pass. Preserve the final 20% of the time budget for verification and demo.

Current repository decisions: Makati starter city, required Taglish planner. Read docs/HACKATHON.md and docs/MAC-SETUP.md when preparing the build. Project docs override the dated portable contract snapshot.
