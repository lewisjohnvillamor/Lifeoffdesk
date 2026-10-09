import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { C, Phone, Words, clamp, ease, useIn } from "../kit";

export const Fog: React.FC = () => {
  const f = useCurrentFrame();
  const phone = useIn(8, 24);
  const km = interpolate(f, [30, 110], [0, 1.81], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: C.canvas }}>
      <div style={{ position: "absolute", left: 140, top: 330, width: 820, textAlign: "left" }}>
        <Words text="Every walk draws your map" at={0} size={104} weight={700} highlight={["map"]} />
        <div style={{ marginTop: 40, fontSize: 40, color: C.secondary, textAlign: "center", opacity: useIn(30) }}>
          Turn an unknown corner and your world grows out of the fog.
        </div>
      </div>
      <div style={{ position: "absolute", right: 250, top: 60, opacity: phone, translate: `0 ${(1 - phone) * 120}px`, rotate: "-3deg",
        scale: String(interpolate(f, [0, 150], [1, 1.05])) }}>
        <Phone src="m2-demo-closeup" width={430} />
      </div>
      <div style={{ position: "absolute", right: 520, bottom: 140, background: C.white, borderRadius: 30, padding: "22px 34px",
        boxShadow: "0 20px 50px rgba(40,58,49,0.2)", opacity: useIn(28) }}>
        <div style={{ fontSize: 72, fontWeight: 800, color: C.ink }}>+{km.toFixed(2)} km</div>
        <div style={{ fontSize: 28, color: C.secondary }}>New streets · sample adventure</div>
      </div>
    </AbsoluteFill>
  );
};
