import React from "react";
import { Composition } from "remotion";
import { LaunchVideo, TOTAL } from "./LaunchVideo";

export const RemotionRoot: React.FC = () => (
  <>
    {/* Square for X and LinkedIn feeds; landscape for the website and YouTube. */}
    <Composition id="LaunchSquare" component={LaunchVideo} width={1080} height={1080} fps={30} durationInFrames={TOTAL} />
    <Composition id="LaunchVideo" component={LaunchVideo} width={1920} height={1080} fps={30} durationInFrames={TOTAL} />
  </>
);
