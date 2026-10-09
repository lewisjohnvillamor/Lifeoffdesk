import React from "react";
import { AbsoluteFill } from "remotion";
import { C, Phone, Words, useIn, useSquare } from "../kit";

export const Memories: React.FC = () => {
  const sq = useSquare();
  const a = useIn(10, 22), b = useIn(18, 22), c = useIn(26, 22);
  const w = sq ? 270 : 300, mid = sq ? 290 : 320;
  const xs = sq ? [110, 395, 700] : [470, 790, 1130];
  const top = sq ? 260 : 270;
  return (
    <AbsoluteFill style={{ background: C.canvas }}>
      <div style={{ position: "absolute", top: sq ? 70 : 70, width: "100%" }}>
        <Words text="Keep the memories" at={0} size={sq ? 84 : 96} weight={800} highlight={["memories"]} />
      </div>
      <div style={{ position: "absolute", left: xs[0], top, rotate: "-8deg", opacity: a, translate: `0 ${(1 - a) * 200}px` }}>
        <Phone src="m8-recap" width={w} />
      </div>
      <div style={{ position: "absolute", left: xs[1], top: top - 40, opacity: b, translate: `0 ${(1 - b) * 200}px`, zIndex: 2 }}>
        <Phone src="m7-card-sticker" width={mid} />
      </div>
      <div style={{ position: "absolute", left: xs[2], top, rotate: "8deg", opacity: c, translate: `0 ${(1 - c) * 200}px` }}>
        <Phone src="m5-adventures-demo" width={w} />
      </div>
    </AbsoluteFill>
  );
};
