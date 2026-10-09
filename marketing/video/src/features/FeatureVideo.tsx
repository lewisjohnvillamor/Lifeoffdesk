import React from "react";
import { AbsoluteFill, Series, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Audio } from "@remotion/media";
import { C, Mascot, Phone, Words, clamp, ease, fontFamily, useIn } from "../kit";
import { Card, Line, Screen, Thinking, Typed, typedDone } from "./ChatKit";
import run from "../chat-run.json";

type Answer = { q: string; title?: string; steps?: string[]; highlights?: string[]; source?: string; emergency?: boolean;
  hotlines?: { name: string; numbers: string[]; source?: string }[]; lost?: string; places?: { name: string; m: number }[] };
const R = run as unknown as Answer[];
const overheat = R[0], cpr = R[1], nlex = R[4], lost = R[6];

/** Phone on the left, caption on the right (square 1080). */
const Stage: React.FC<{ kicker: string; title: string; note: string; children: React.ReactNode }> = ({ kicker, title, note, children }) => {
  const a = useIn(0, 16);
  return (
    <AbsoluteFill style={{ background: C.white }}>
      <div style={{ position: "absolute", left: 40, top: 70, scale: "0.98" }}>{children}</div>
      <div style={{ position: "absolute", left: 540, top: 140, width: 480, opacity: a, translate: `${(1 - a) * 40}px 0` }}>
        <div style={{ fontSize: 26, fontWeight: 700, color: C.primary, letterSpacing: 1 }}>{kicker}</div>
        <div style={{ fontSize: 58, fontWeight: 800, color: C.ink, lineHeight: 1.08, marginTop: 14, letterSpacing: -1 }}>{title}</div>
        <div style={{ fontSize: 26, color: C.secondary, marginTop: 22, lineHeight: 1.35 }}>{note}</div>
      </div>
    </AbsoluteFill>
  );
};

const Hotline: React.FC<{ at: number; name: string; numbers: string[]; source?: string }> = ({ at, name, numbers, source }) => (
  <Line at={at} style={{ display: "flex", flexDirection: "column", gap: 4 }}>
    <div style={{ fontSize: 16, fontWeight: 700, color: C.ink }}>{name}</div>
    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
      {numbers.slice(0, 2).map((n) => (
        <span key={n} style={{ fontSize: 15, fontWeight: 700, color: C.primary, background: "#E6EDE2", borderRadius: 99, padding: "5px 9px" }}>📞 {n}</span>
      ))}
    </div>
    {source ? <div style={{ fontSize: 12, color: C.secondary }}>Source: {source}</div> : null}
  </Line>
);

const Intro: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: "#0B0D0C", justifyContent: "center", alignItems: "center", flexDirection: "column", gap: 30 }}>
      <div style={{ fontSize: 90, opacity: interpolate(f, [0, 12], [0, 1], clamp) }}>✈︎</div>
      <div style={{ width: 900 }}><Words text="Airplane Mode on. Let's try it." at={8} size={76} weight={700} color="#F8F6EF" /></div>
      <div style={{ fontSize: 28, color: "#9DB5A6", opacity: interpolate(f, [40, 56], [0, 1], clamp) }}>Life Off Desk · help chat and maps, all offline</div>
    </AbsoluteFill>
  );
};

const Overheat: React.FC = () => {
  const done = typedDone(10, overheat.q);
  return (
    <Stage kicker="ASK IN TAGLISH" title="Points you to the exact step" note="It finds the lines in the reviewed card that answer your question. No made-up advice.">
      <Screen title="Help assistant">
        <Typed at={10} text={overheat.q} />
        <Thinking from={done + 2} to={done + 20} />
        <Card at={done + 20}>
          <div style={{ background: "#E6EDE2", borderRadius: 12, padding: 10, display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ fontSize: 15, fontWeight: 700, color: C.primary }}>Sagot sa tanong mo (mula sa card):</div>
            {overheat.highlights!.map((h, i) => (
              <Line key={i} at={done + 28 + i * 10} style={{ fontSize: 16, fontWeight: 600, color: C.ink }}>“{h}”</Line>
            ))}
          </div>
          <Line at={done + 50} style={{ fontSize: 19, fontWeight: 700, color: C.ink }}>{overheat.title}</Line>
          {overheat.steps!.slice(2, 4).map((s, i) => (
            <Line key={i} at={done + 56 + i * 6} style={{ fontSize: 15, color: C.ink }}>{i + 3}. {s}</Line>
          ))}
          <Line at={done + 76} style={{ fontSize: 14, color: C.primary }}>Source: {overheat.source}</Line>
        </Card>
      </Screen>
    </Stage>
  );
};

const Emergency: React.FC = () => {
  const done = typedDone(10, cpr.q);
  return (
    <Stage kicker="EMERGENCIES FIRST" title="911, your city's rescue line, then the steps" note="Emergency words always raise the Call 911 button. The AI can add an alert, never remove one.">
      <Screen title="Help assistant">
        <Typed at={10} text={cpr.q} />
        <Thinking from={done + 2} to={done + 16} />
        <Card at={done + 16} border={C.danger}>
          <div style={{ background: C.danger, color: C.white, borderRadius: 12, padding: "11px 10px", fontSize: 18, fontWeight: 700, textAlign: "center" }}>
            📞 Mukhang emergency ito. Call 911 now
          </div>
          <Line at={done + 26} style={{ fontSize: 15, fontWeight: 700, color: C.ink }}>Iba pang matatawagan:</Line>
          {cpr.hotlines!.slice(0, 1).map((h, i) => <Hotline key={h.name} at={done + 32 + i * 8} name={h.name} numbers={h.numbers} />)}
          <Line at={done + 52} style={{ fontSize: 19, fontWeight: 700, color: C.ink }}>{cpr.title}</Line>
          {cpr.steps!.slice(2, 4).map((s, i) => (
            <Line key={i} at={done + 58 + i * 6} style={{ fontSize: 15, color: C.ink }}>{i + 3}. {s}</Line>
          ))}
        </Card>
      </Screen>
    </Stage>
  );
};

const Hotlines: React.FC = () => {
  const done = typedDone(10, nlex.q);
  const h = nlex.hotlines![0];
  return (
    <Stage kicker="LOCAL HOTLINES" title="Expressways, LGUs, Red Cross, MMDA" note="26 Philippine hotlines bundled offline, each with its source. Looked up by code, never generated.">
      <Screen title="Help assistant">
        <Typed at={10} text={nlex.q} />
        <Card at={done + 14}>
          <div style={{ fontSize: 16, fontWeight: 700, color: C.ink }}>Hotlines na nahanap</div>
          <Hotline at={done + 20} name={h.name} numbers={h.numbers} source={h.source} />
          <Line at={done + 30} style={{ fontSize: 12, color: C.secondary }}>Offline copy; numbers can change. 911 works nationwide.</Line>
        </Card>
      </Screen>
    </Stage>
  );
};

const Lost: React.FC = () => {
  const q1 = "naligaw ako";
  const d1 = typedDone(8, q1);
  const q2 = "Greenbelt";
  const at2 = d1 + 64;
  const d2 = typedDone(at2, q2);
  return (
    <Stage kicker="LOST? IT'S A CONVERSATION" title="Where you are, then where to go" note="Offline GPS and the nearest named place, then a search of the offline map with a Route button. Demo location in Makati.">
      <Screen title="Help assistant">
        <Typed at={8} text={q1} />
        <Card at={d1 + 12}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.ink }}>📍 Nasaan ka ngayon</div>
          <Line at={d1 + 18} style={{ fontSize: 15, color: C.ink }}>{lost.lost}</Line>
        </Card>
        <Card at={d1 + 34}>
          <div style={{ fontSize: 16, color: C.ink }}>Saan mo gustong pumunta? I-type ang lugar o landmark na nakikita mo.</div>
        </Card>
        <Typed at={at2} text={q2} cps={0.8} />
        <Card at={d2 + 12}>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.ink }}>Nakita sa offline map:</div>
          {lost.places!.slice(0, 2).map((p, i) => (
            <Line key={p.name} at={d2 + 18 + i * 8} style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 16, fontWeight: 600, color: C.ink }}>{p.name}</div>
                <div style={{ fontSize: 14, color: C.secondary }}>{p.m} m straight-line</div>
              </div>
              <span style={{ background: C.primary, color: C.white, borderRadius: 10, padding: "6px 12px", fontSize: 15, fontWeight: 700 }}>Route</span>
            </Line>
          ))}
        </Card>
      </Screen>
    </Stage>
  );
};

const Walk: React.FC = () => {
  const a = useIn(6, 20), b = useIn(40, 20);
  return (
    <AbsoluteFill style={{ background: C.canvas }}>
      <div style={{ position: "absolute", top: 60, width: "100%" }}>
        <Words text="Route, walk, arrive" at={0} size={76} weight={800} highlight={["arrive"]} />
      </div>
      <div style={{ position: "absolute", left: 150, top: 200, rotate: "-4deg", opacity: a, translate: `0 ${(1 - a) * 120}px` }}>
        <Phone src="m6-route" width={330} />
      </div>
      <div style={{ position: "absolute", left: 580, top: 220, rotate: "4deg", opacity: b, translate: `0 ${(1 - b) * 120}px` }}>
        <Phone src="m8-recap" width={330} />
      </div>
    </AbsoluteFill>
  );
};

const Outro: React.FC = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.white, justifyContent: "center", alignItems: "center", flexDirection: "column", gap: 24 }}>
      <Mascot pose="celebrating" size={190} />
      <div style={{ fontSize: 92, fontWeight: 800, color: C.ink, letterSpacing: -3 }}>Life Off Desk</div>
      <div style={{ width: 900 }}><Words text="Useful when the signal isn't." at={14} size={50} weight={600} color={C.secondary} /></div>
      <div style={{ position: "absolute", bottom: 46, width: 960, textAlign: "center", fontSize: 21, color: C.secondary, lineHeight: 1.35,
        opacity: interpolate(f, [40, 60], [0, 1], { ...clamp, easing: ease }) }}>
        Chat answers shown are the real output of the app's offline routing code (keyword layer; on the phone the on-device AI also routes). Map screens from the labelled demo world.
      </div>
    </AbsoluteFill>
  );
};

export const FEATURE_SCENES = [
  { name: "Intro", durationInFrames: 90, component: Intro },
  { name: "Overheat", durationInFrames: 270, component: Overheat },
  { name: "Emergency", durationInFrames: 240, component: Emergency },
  { name: "Hotlines", durationInFrames: 150, component: Hotlines },
  { name: "Lost", durationInFrames: 270, component: Lost },
  { name: "Walk", durationInFrames: 120, component: Walk },
  { name: "Outro", durationInFrames: 150, component: Outro },
];
export const FEATURE_TOTAL = FEATURE_SCENES.reduce((s, x) => s + x.durationInFrames, 0);

export const FeatureVideo: React.FC = () => (
  <AbsoluteFill style={{ fontFamily }}>
    {/* Same Mixkit Free License track as the launch film, from a later section. */}
    <Audio src={staticFile("music/just-keep-walking.mp3")} trimBefore={40 * 30}
      volume={(f) => interpolate(f, [0, 20, FEATURE_TOTAL - 60, FEATURE_TOTAL], [0, 0.7, 0.7, 0], clamp)} />
    <Series>
      {FEATURE_SCENES.map(({ name, durationInFrames, component: Scene }) => (
        <Series.Sequence key={name} name={name} durationInFrames={durationInFrames}><Scene /></Series.Sequence>
      ))}
    </Series>
  </AbsoluteFill>
);
