import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Mascot, Words, clamp, ease, useSquare } from "../kit";

export const Coach: React.FC = () => {
  const f = useCurrentFrame();
  const sq = useSquare();
  const up = interpolate(f, [60, 80], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.white, justifyContent: "center", alignItems: "center" }}>
      <div style={{ position: "absolute", top: interpolate(up, [0, 1], sq ? [380, 90] : [430, 170]), width: sq ? 960 : 1600,
        scale: String(interpolate(up, [0, 1], [1, sq ? 0.7 : 0.62])) }}>
        <Words text="Notices when your world gets smaller" at={0} every={5} size={sq ? 100 : 124} weight={800} highlight={["smaller"]} />
      </div>
      <div style={{ position: "absolute", top: sq ? 380 : 430, width: sq ? 940 : 1100, display: "flex", flexDirection: "column", gap: 20, opacity: up }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <Mascot pose="thinking" size={84} />
          <div style={{ fontSize: 26, color: C.secondary, fontWeight: 600 }}>Computed from your walks · worded by on-device AI</div>
        </div>
        <Bubble at={84} sub="It's been a while. Last adventure: 5 days ago.">Tagal mo nang di lumalabas. Huling adventure: 5 araw na.</Bubble>
        <Bubble at={112} sub="How about Salcedo Park?">Tara sa Salcedo Park?</Bubble>
        <Bubble at={140} out>Tara!</Bubble>
      </div>
    </AbsoluteFill>
  );
};
