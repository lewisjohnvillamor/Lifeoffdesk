import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Mascot, Phone, clamp, ease, usePop } from "../kit";

// Real app strings: the coach line (CoachRenderer), "Tara!" and the arrival card (MapScreen).
export const ColdOpen: React.FC = () => {
  const f = useCurrentFrame();
  const pull = interpolate(f, [130, 165], [0, 1], { ...clamp, easing: ease });
  const arrive = usePop(195);
  return (
    <AbsoluteFill style={{ background: C.white }}>
      <div
        style={{
          position: "absolute", left: interpolate(pull, [0, 1], [460, 150]), top: interpolate(pull, [0, 1], [250, 300]),
          width: 1000, scale: String(interpolate(pull, [0, 1], [1, 0.72])), transformOrigin: "left top",
          display: "flex", flexDirection: "column", gap: 22,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18, opacity: usePop(4) }}>
          <Mascot pose="thinking" size={92} />
          <div style={{ fontSize: 30, color: C.secondary, fontWeight: 600 }}>Life Off Desk · on-device AI</div>
        </div>
        <Bubble at={12}>Uy, lumiliit ang mundo mo!</Bubble>
        <Bubble at={38}>Pinakamalayo mo: 2.40 km → 600 m.</Bubble>
        <Bubble at={64}>Game? May new streets pa-hilaga (450 m).</Bubble>
        <Bubble at={100} out>Tara! 🐾</Bubble>
      </div>
      <div
        style={{
          position: "absolute", right: 260, top: 70, opacity: pull,
          translate: `${interpolate(pull, [0, 1], [400, 0])}px 0`,
        }}
      >
        <Phone src="m6-route" width={430} />
      </div>
      <div
        style={{
          position: "absolute", right: 150, top: 640, width: 660, padding: "30px 34px", borderRadius: 34,
          background: C.white, boxShadow: "0 24px 60px rgba(40,58,49,0.22)", opacity: arrive,
          scale: String(0.7 + 0.3 * arrive), display: "flex", flexDirection: "column", gap: 18,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <div style={{ fontSize: 46 }}>🏁</div>
          <div>
            <div style={{ fontSize: 40, fontWeight: 700, color: C.ink }}>Nakarating ka na!</div>
            <div style={{ fontSize: 28, color: C.secondary }}>You&apos;ve arrived. New streets added.</div>
          </div>
        </div>
        <div style={{ display: "flex", gap: 14 }}>
          <div style={{ background: C.primary, color: C.white, borderRadius: 99, padding: "14px 26px", fontSize: 26, fontWeight: 600 }}>End adventure</div>
          <div style={{ background: "#E6EDE2", color: C.ink, borderRadius: 99, padding: "14px 26px", fontSize: 26, fontWeight: 600 }}>Keep exploring</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
