import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, Mascot, Words, clamp, ease, usePop } from "../kit";

export const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const swap = interpolate(f, [80, 96], [0, 1], { ...clamp, easing: ease });
  const logo = usePop(22);
  return (
    <AbsoluteFill style={{ background: C.white, justifyContent: "center", alignItems: "center" }}>
      <div style={{ opacity: 1 - swap, display: "flex", alignItems: "center", gap: 28, position: "absolute" }}>
        <Words text="Introducing" at={0} size={96} weight={500} />
        <Mascot pose="welcome" size={150} style={{ opacity: logo, scale: String(0.5 + 0.5 * logo) }} />
        <div style={{ fontSize: 96, fontWeight: 700, color: C.ink, opacity: logo, letterSpacing: -2 }}>Life Off Desk</div>
      </div>
      <div style={{ opacity: swap, position: "absolute", width: 1500 }}>
        <Words text="There's more to life than your screen" at={90} every={4} size={100} weight={700} highlight={["life"]} />
      </div>
    </AbsoluteFill>
  );
};
