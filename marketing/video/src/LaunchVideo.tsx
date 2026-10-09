import React from "react";
import { AbsoluteFill, Series, interpolate, staticFile } from "remotion";
import { Audio } from "@remotion/media";
import { fontFamily } from "./kit";
import { ColdOpen } from "./scenes/ColdOpen";
import { Intro } from "./scenes/Intro";
import { Fog } from "./scenes/Fog";
import { Coach } from "./scenes/Coach";
import { Help } from "./scenes/Help";
import { Local } from "./scenes/Local";
import { Memories } from "./scenes/Memories";
import { EndCard } from "./scenes/EndCard";
import { Outside } from "./scenes/Outside";

export const SCENES = [
  { name: "Cold open", durationInFrames: 300, component: ColdOpen },
  { name: "Intro", durationInFrames: 170, component: Intro },
  { name: "Fog", durationInFrames: 150, component: Fog },
  { name: "Coach", durationInFrames: 190, component: Coach },
  { name: "Help", durationInFrames: 220, component: Help },
  { name: "Local", durationInFrames: 140, component: Local },
  { name: "Memories", durationInFrames: 130, component: Memories },
  { name: "Outside", durationInFrames: 230, component: Outside },
  { name: "End card", durationInFrames: 150, component: EndCard },
];
export const TOTAL = SCENES.reduce((s, x) => s + x.durationInFrames, 0);

export const LaunchVideo: React.FC = () => (
  <AbsoluteFill style={{ fontFamily }}>
    {/* "Just Keep Walking" by Michael Ramir C. (Mixkit Free License), faded in and out. */}
    <Audio
      src={staticFile("music/just-keep-walking.mp3")}
      volume={(f) => interpolate(f, [0, 20, TOTAL - 60, TOTAL], [0, 0.8, 0.8, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}
    />
    <Series>
      {SCENES.map(({ name, durationInFrames, component: Scene }) => (
        <Series.Sequence key={name} name={name} durationInFrames={durationInFrames}>
          <Scene />
        </Series.Sequence>
      ))}
    </Series>
  </AbsoluteFill>
);
