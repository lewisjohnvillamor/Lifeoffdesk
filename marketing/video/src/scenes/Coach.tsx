import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Mascot, Words, clamp, ease } from "../kit";

export const Coach: React.FC = () => {
  const f = useCurrentFrame();
  const up = interpolate(f, [60, 80], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.white, justifyContent: "center", alignItems: "center" }}>
      <div style={{ position: "absolute", top: interpolate(up, [0, 1], [430, 170]), width: 1600,
        scale: String(interpolate(up, [0, 1], [1, 0.62])) }}>
        <Words text="Notices when your world gets smaller" at={0} every={5} size={124} weight={800} highlight={["smaller"]} />
      </div>
      <div style={{ position: "absolute", top: 430, width: 1100, display: "flex", flexDirection: "column", gap: 22, opacity: up }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <Mascot pose="thinking" size={84} />
          <div style={{ fontSize: 28, color: C.secondary, fontWeight: 600 }}>Computed from your walks · worded by on-device AI</div>
        </div>
        <Bubble at={84}>Tagal mo nang di lumalabas. Huling adventure: 5 araw na.</Bubble>
        <Bubble at={110}>Tara sa Salcedo Park?</Bubble>
        <Bubble at={140} out>Tara!</Bubble>
      </div>
    </AbsoluteFill>
  );
};
