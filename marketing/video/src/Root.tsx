import React from "react";
import { Composition } from "remotion";
import { LaunchVideo, TOTAL } from "./LaunchVideo";

export const RemotionRoot: React.FC = () => (
  <Composition id="LaunchVideo" component={LaunchVideo} width={1920} height={1080} fps={30} durationInFrames={TOTAL} />
);
