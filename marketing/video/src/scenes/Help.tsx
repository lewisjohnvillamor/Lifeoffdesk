import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Phone, Words, clamp, ease, useIn, useSquare } from "../kit";

// Questions and answers as the app's help chat shows them (bundled, sourced cards and hotlines).
export const Help: React.FC = () => {
  const f = useCurrentFrame();
  const sq = useSquare();
  const phone = useIn(120, 26);
  const shift = interpolate(f, [110, 140], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.white }}>
      <div style={{ position: "absolute", top: sq ? 60 : 90, width: "100%" }}>
        <Words text="Help, even with no signal" at={0} size={sq ? 80 : 96} weight={800} highlight={["no", "signal"]} />
      </div>
      <div style={{ position: "absolute", left: interpolate(shift, [0, 1], sq ? [70, 40] : [410, 150]), top: sq ? 210 : 280,
        width: sq ? 960 : 1100, scale: String(sq ? interpolate(shift, [0, 1], [1, 0.62]) : 1), transformOrigin: "left top",
        display: "flex", flexDirection: "column", gap: 16 }}>
        <Bubble at={20} out sub="My tire blew on EDSA, how do I change it?">nasira gulong ko sa EDSA, paano magpalit?</Bubble>
        <Bubble at={44}>Flat tire (gulong): changing to the spare</Bubble>
        <Bubble at={70} out sub="Someone collapsed, grandma isn't breathing">may nahimatay, hindi humihinga si lola</Bubble>
        <Bubble at={94} tint={C.danger}>📞 Mukhang emergency ito. Call 911 now</Bubble>
      </div>
      <div style={{ position: "absolute", right: sq ? 60 : 200, top: sq ? 250 : 250, opacity: phone, translate: `${(1 - phone) * 300}px 0`, rotate: "3deg" }}>
        <Phone src="m9-help-chat-emergency" width={sq ? 320 : 360} />
      </div>
    </AbsoluteFill>
  );
};
