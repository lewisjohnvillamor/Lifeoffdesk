import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Bubble, C, Phone, Words, clamp, ease, useIn } from "../kit";

// Questions and card titles as they appear in the app's help chat (bundled, sourced cards).
export const Help: React.FC = () => {
  const f = useCurrentFrame();
  const phone = useIn(120, 26);
  const shift = interpolate(f, [110, 140], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.white }}>
      <div style={{ position: "absolute", top: 90, width: "100%" }}>
        <Words text="Help, even with no signal" at={0} size={96} weight={800} highlight={["no", "signal"]} />
      </div>
      <div style={{ position: "absolute", left: interpolate(shift, [0, 1], [410, 150]), top: 300, width: 1100,
        display: "flex", flexDirection: "column", gap: 20 }}>
        <Bubble at={20} out>nasira gulong ko sa EDSA, paano magpalit?</Bubble>
        <Bubble at={44}>Flat tire (gulong): changing to the spare</Bubble>
        <Bubble at={70} out>may nahimatay, hindi humihinga si lola</Bubble>
        <Bubble at={94} tint={C.danger}>📞 Mukhang emergency ito. Call 911 now</Bubble>
      </div>
      <div style={{ position: "absolute", right: 200, top: 250, opacity: phone, translate: `${(1 - phone) * 300}px 0`, rotate: "3deg" }}>
        <Phone src="m9-help-chat-emergency" width={360} />
      </div>
    </AbsoluteFill>
  );
};
