import React from "react";
import { AbsoluteFill, Series, interpolate, staticFile } from "remotion";
import { Audio } from "@remotion/media";
import { fontFamily } from "./kit";
import { ColdOpen } from "./scenes/ColdOpen";
import { Intro } from "./scenes/Intro";
import { Fog } from "./scenes/Fog";
import { Local } from "./scenes/Local";
import { Memories } from "./scenes/Memories";
import { EndCard } from "./scenes/EndCard";
import { Outside } from "./scenes/Outside";
import { Emergency, Hotlines, Lost, Overheat } from "./features/FeatureVideo";

// Under 60 s for X/LinkedIn: story, then the help chat running for real, then the close.
export const SCENES = [
  { name: "Cold open", durationInFrames: 260, component: ColdOpen },
  { name: "Intro", durationInFrames: 150, component: Intro },
  { name: "Fog", durationInFrames: 120, component: Fog },
  { name: "Chat: overheat", durationInFrames: 200, component: Overheat },
  { name: "Chat: emergency", durationInFrames: 190, component: Emergency },
  { name: "Chat: hotlines", durationInFrames: 110, component: Hotlines },
  { name: "Chat: lost", durationInFrames: 210, component: Lost },
  { name: "Local", durationInFrames: 120, component: Local },
  { name: "Memories", durationInFrames: 90, component: Memories },
  { name: "Outside", durationInFrames: 200, component: Outside },
  { name: "End card", durationInFrames: 120, component: EndCard },
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
