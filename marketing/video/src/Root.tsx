import React from "react";
import { Composition } from "remotion";
import { LaunchVideo, TOTAL } from "./LaunchVideo";
import { FeatureVideo, FEATURE_TOTAL } from "./features/FeatureVideo";

export const RemotionRoot: React.FC = () => (
  <>
    {/* Square for X and LinkedIn feeds; landscape for the website and YouTube. */}
    <Composition id="LaunchSquare" component={LaunchVideo} width={1080} height={1080} fps={30} durationInFrames={TOTAL} />
    {/* Second film: the features, with chat answers from the app's own offline code. */}
    <Composition id="FeaturesSquare" component={FeatureVideo} width={1080} height={1080} fps={30} durationInFrames={FEATURE_TOTAL} />
    <Composition id="LaunchVideo" component={LaunchVideo} width={1920} height={1080} fps={30} durationInFrames={TOTAL} />
  </>
);
