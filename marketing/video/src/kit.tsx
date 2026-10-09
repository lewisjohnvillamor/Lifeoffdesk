import React from "react";
import { Easing, Img, continueRender, delayRender, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

/** Square (1080×1080, for X and LinkedIn feeds) vs landscape (1920×1080). */
export const useSquare = () => {
  const { width, height } = useVideoConfig();
  return width === height;
};

// Inter (SIL OFL, from @fontsource/inter) bundled locally so rendering needs no network.
const fontHandle = delayRender("Loading Inter");
Promise.all(
  [400, 500, 600, 700, 800].map((w) =>
    new FontFace("Inter", `url(${staticFile(`fonts/inter-latin-${w}-normal.woff2`)}) format('woff2')`, { weight: String(w) })
      .load()
      .then((face) => document.fonts.add(face)),
  ),
).then(() => continueRender(fontHandle));
export const fontFamily = "Inter, sans-serif";

// Brand tokens (docs/BRAND-GUIDE.md).
export const C = {
  canvas: "#F8F6EF",
  ink: "#283A31",
  primary: "#46785B",
  secondary: "#69776D",
  danger: "#A13D36",
  bubble: "#ECEAE3",
  white: "#FFFFFF",
};

export const ease = Easing.bezier(0.16, 1, 0.3, 1);
export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** 0→1 with an ease-out over `dur` frames starting at `at`. */
export const useIn = (at: number, dur = 18) => {
  const f = useCurrentFrame();
  return interpolate(f, [at, at + dur], [0, 1], { ...clamp, easing: ease });
};

/** Springy pop for chat bubbles. */
export const usePop = (at: number) => {
  const f = useCurrentFrame();
  return interpolate(f, [at, at + 14], [0, 1], { ...clamp, easing: Easing.spring({ damping: 14, stiffness: 180 }) });
};

export const Bubble: React.FC<{ at: number; out?: boolean; children: React.ReactNode; size?: number; maxWidth?: number; tint?: string; sub?: string }> = ({
  at, out, children, size = 40, maxWidth = 760, tint, sub,
}) => {
  const p = usePop(at);
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: out ? "flex-end" : "flex-start", width: "100%", gap: size * 0.18 }}>
      <div
        style={{
          opacity: Math.min(1, p * 1.4),
          scale: String(0.6 + 0.4 * p),
          transformOrigin: out ? "right bottom" : "left bottom",
          background: tint ?? (out ? C.primary : C.bubble),
          color: out || tint ? C.white : C.ink,
          fontSize: size,
          lineHeight: 1.25,
          padding: `${size * 0.42}px ${size * 0.6}px`,
          borderRadius: size * 0.9,
          maxWidth,
          fontWeight: 500,
          boxShadow: "0 6px 24px rgba(40,58,49,0.08)",
        }}
      >
        {children}
      </div>
      {sub ? (
        <div style={{ opacity: Math.min(1, p * 1.2) * 0.9, fontSize: size * 0.62, color: C.secondary, fontStyle: "italic", maxWidth, padding: `0 ${size * 0.4}px` }}>
          {sub}
        </div>
      ) : null}
    </div>
  );
};

/** iPhone-style frame around a real app screenshot (1242×2688 captures). */
export const Phone: React.FC<{ src: string; width: number; style?: React.CSSProperties }> = ({ src, width, style }) => {
  const h = width * (2688 / 1242);
  const bezel = width * 0.035;
  return (
    <div
      style={{
        width: width + bezel * 2,
        height: h + bezel * 2,
        borderRadius: width * 0.16,
        background: "#1C1F1D",
        padding: bezel,
        boxShadow: "0 40px 90px rgba(40,58,49,0.25)",
        ...style,
      }}
    >
      <div style={{ width, height: h, borderRadius: width * 0.13, overflow: "hidden", position: "relative", background: C.canvas }}>
        <Img src={staticFile(`shots/${src}.jpg`)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        <div
          style={{
            position: "absolute", top: width * 0.025, left: "50%", translate: "-50% 0",
            width: width * 0.3, height: width * 0.085, borderRadius: 99, background: "#111",
          }}
        />
      </div>
    </div>
  );
};

export const Mascot: React.FC<{ pose: string; size: number; style?: React.CSSProperties }> = ({ pose, size, style }) => (
  <Img src={staticFile(`mascot/mascot-${pose}.png`)} style={{ width: size, height: size, objectFit: "contain", ...style }} />
);

/** Words appear one by one (blur-in), like a typed headline. */
export const Words: React.FC<{ text: string; at: number; every?: number; size: number; color?: string; weight?: number; highlight?: string[] }> = ({
  text, at, every = 5, size, color = C.ink, weight = 600, highlight = [],
}) => {
  const f = useCurrentFrame();
  return (
    <div style={{ fontSize: size, fontWeight: weight, color, letterSpacing: -size * 0.02, lineHeight: 1.12, textAlign: "center" }}>
      {text.split(" ").map((w, i) => {
        const p = interpolate(f, [at + i * every, at + i * every + 12], [0, 1], { ...clamp, easing: ease });
        return (
          <span
            key={i}
            style={{
              display: "inline-block", marginRight: size * 0.25, opacity: p, filter: `blur(${(1 - p) * 10}px)`,
              translate: `0 ${(1 - p) * 18}px`, color: highlight.includes(w) ? C.primary : undefined,
            }}
          >
            {w}
          </span>
        );
      })}
    </div>
  );
};
