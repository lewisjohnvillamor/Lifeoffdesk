import React from "react";
import { AbsoluteFill } from "remotion";
import { C, Phone, Words, useIn } from "../kit";

export const Memories: React.FC = () => {
  const a = useIn(10, 22), b = useIn(18, 22), c = useIn(26, 22);
  return (
    <AbsoluteFill style={{ background: C.canvas }}>
      <div style={{ position: "absolute", top: 70, width: "100%" }}>
        <Words text="Keep the memories" at={0} size={96} weight={800} highlight={["memories"]} />
      </div>
      <div style={{ position: "absolute", left: 470, top: 270, rotate: "-8deg", opacity: a, translate: `0 ${(1 - a) * 200}px` }}>
        <Phone src="m8-recap" width={300} />
      </div>
      <div style={{ position: "absolute", left: 790, top: 230, opacity: b, translate: `0 ${(1 - b) * 200}px`, zIndex: 2 }}>
        <Phone src="m7-card-sticker" width={320} />
      </div>
      <div style={{ position: "absolute", left: 1130, top: 270, rotate: "8deg", opacity: c, translate: `0 ${(1 - c) * 200}px` }}>
        <Phone src="m5-adventures-demo" width={300} />
      </div>
    </AbsoluteFill>
  );
};
