import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, Mascot, Words, clamp, ease, usePop } from "../kit";

export const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const logo = usePop(0);
  const cta = usePop(60);
  return (
    <AbsoluteFill style={{ background: C.white, justifyContent: "center", alignItems: "center", flexDirection: "column", gap: 30 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 26, opacity: logo, scale: String(0.7 + 0.3 * logo) }}>
        <Mascot pose="walking" size={170} />
        <div style={{ fontSize: 110, fontWeight: 800, color: C.ink, letterSpacing: -3 }}>Life Off Desk</div>
      </div>
      <Words text="There's more to life than your screen" at={22} every={3} size={54} weight={500} color={C.secondary} highlight={["life"]} />
      <div style={{ marginTop: 20, background: C.primary, color: C.white, borderRadius: 99, padding: "24px 56px", fontSize: 44,
        fontWeight: 700, opacity: cta, scale: String(0.7 + 0.3 * cta) }}>
        🚶 Start exploring
      </div>
      <div style={{ position: "absolute", bottom: 70, fontSize: 28, color: C.secondary, opacity: interpolate(f, [80, 100], [0, 1], { ...clamp, easing: ease }) }}>
        AppBuildersPH Hackathon 2026 · Local AI · screens from the app&apos;s labelled demo world
      </div>
    </AbsoluteFill>
  );
};
