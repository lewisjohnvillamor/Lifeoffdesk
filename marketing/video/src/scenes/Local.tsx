import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Words, clamp, ease, useSquare } from "../kit";

export const Local: React.FC = () => {
  const f = useCurrentFrame();
  const sq = useSquare();
  const a = interpolate(f, [62, 76], [1, 0], { ...clamp, easing: ease });
  const b = interpolate(f, [70, 84], [0, 1], { ...clamp, easing: ease });
  return (
    <AbsoluteFill style={{ background: "#0B0D0C", justifyContent: "center", alignItems: "center" }}>
      <div style={{ position: "absolute", opacity: a, width: sq ? 900 : 1600 }}>
        <Words text="✈︎ Runs on your iPhone." at={0} size={sq ? 88 : 104} weight={600} color="#F8F6EF" />
      </div>
      <div style={{ position: "absolute", opacity: b, display: "flex", flexDirection: "column", alignItems: "center", gap: 36, width: sq ? 900 : 1700 }}>
        <Words text="No internet. No cloud. No account." at={72} size={sq ? 80 : 92} weight={600} color="#F8F6EF" />
        <div style={{ fontSize: sq ? 30 : 34, color: "#9DB5A6", textAlign: "center", opacity: interpolate(f, [100, 116], [0, 1], clamp) }}>
          On-device AI · Qwen3-1.7B with llama.cpp · Apple on-device speech &amp; vision
        </div>
      </div>
    </AbsoluteFill>
  );
};
