import React from "react";
import { AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Video } from "@remotion/media";
import { Words, clamp, ease, useSquare } from "../kit";

// Stock footage (Mixkit Free License): closing the laptop, then a sunny walk outside.
export const Outside: React.FC = () => {
  const f = useCurrentFrame();
  const sq = useSquare();
  const swap = interpolate(f, [100, 112], [0, 1], { ...clamp, easing: ease });
  const { width, height } = useVideoConfig();
  // 16:9 footage: cover the frame by height in the square cut, cropped at the sides.
  const w = Math.max(width, (height * 16) / 9);
  const cover: React.CSSProperties = { position: "absolute", width: w, height: (w * 9) / 16, left: (width - w) / 2, top: (height - (w * 9) / 16) / 2 };
  const shade = "linear-gradient(180deg, rgba(0,0,0,0) 45%, rgba(0,0,0,0.55) 100%)";
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <Sequence durationInFrames={112}>
        <Video src={staticFile("stock/laptop.mp4")} muted style={cover} />
      </Sequence>
      <Sequence from={100}>
        <AbsoluteFill style={{ opacity: swap }}>
          <Video src={staticFile("stock/park.mp4")} muted style={cover} />
        </AbsoluteFill>
      </Sequence>
      <AbsoluteFill style={{ background: shade }} />
      <div style={{ position: "absolute", bottom: sq ? 110 : 120, width: "100%", opacity: 1 - swap }}>
        <Words text="Close the laptop." at={10} size={sq ? 88 : 100} weight={700} color="#FFFFFF" />
      </div>
      <div style={{ position: "absolute", bottom: sq ? 110 : 120, width: "100%", opacity: swap }}>
        <Words text="Go see your world." at={112} size={sq ? 88 : 100} weight={700} color="#FFFFFF" highlight={[]} />
      </div>
    </AbsoluteFill>
  );
};
