import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Mascot, Phone, clamp, ease, usePop, useSquare } from "../kit";

// The coach's voice (Taglish, English subtitles), the real route screen and the arrival card.
export const ColdOpen: React.FC = () => {
  const f = useCurrentFrame();
  const sq = useSquare();
  const pull = interpolate(f, [150, 185], [0, 1], { ...clamp, easing: ease });
  const arrive = usePop(215);
  const chat = sq
    ? { left: [70, 40], top: [150, 120], width: 940, scale: [1, 0.56] }
    : { left: [420, 130], top: [170, 210], width: 1080, scale: [1, 0.68] };
  return (
    <AbsoluteFill style={{ background: C.white }}>
      <div
        style={{
          position: "absolute", left: interpolate(pull, [0, 1], chat.left), top: interpolate(pull, [0, 1], chat.top),
          width: chat.width, scale: String(interpolate(pull, [0, 1], chat.scale)), transformOrigin: "left top",
          display: "flex", flexDirection: "column", gap: 20,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18, opacity: usePop(4) }}>
          <Mascot pose="thinking" size={92} />
          <div style={{ fontSize: 30, color: C.secondary, fontWeight: 600 }}>Life Off Desk · on-device AI</div>
        </div>
        <Bubble at={12} sub="Psst… your world is getting smaller.">Uyyy, lumiliit na ang mundo mo!</Bubble>
        <Bubble at={44} sub="Time to get some fresh air.">Oras na para makapagpahangin ka naman.</Bubble>
        <Bubble at={76} sub="Up for it? I've got a new adventure for you.">Game? May new adventure ako para sa&apos;yo (450 m).</Bubble>
        <Bubble at={116} out sub="Let's go!">Tara! 🐾</Bubble>
      </div>
      <div
        style={{
          position: "absolute", right: sq ? 70 : 260, top: sq ? 120 : 70, opacity: pull,
          translate: `${interpolate(pull, [0, 1], [400, 0])}px 0`,
        }}
      >
        <Phone src="m6-route" width={sq ? 380 : 430} />
      </div>
      <div
        style={{
          position: "absolute", right: sq ? 60 : 150, top: sq ? 700 : 640, width: sq ? 620 : 660, padding: "28px 32px", borderRadius: 34,
          background: C.white, boxShadow: "0 24px 60px rgba(40,58,49,0.22)", opacity: arrive,
          scale: String(0.7 + 0.3 * arrive), display: "flex", flexDirection: "column", gap: 16,
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
