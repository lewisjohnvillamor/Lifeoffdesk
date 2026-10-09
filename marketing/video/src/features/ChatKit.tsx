import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { C, clamp, ease, usePop } from "../kit";

// A recreation of the app's help-chat screen (SafetyChatView) at phone scale. Text content comes
// from chat-run.json, produced by running the app's own offline routing code (scripts in README).
export const W = 400; // screen width in px
export const H = Math.round(W * (2688 / 1242));

export const Screen: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <div style={{ width: W + 28, height: H + 28, borderRadius: 64, background: "#1C1F1D", padding: 14, boxShadow: "0 40px 90px rgba(40,58,49,0.25)" }}>
    <div style={{ width: W, height: H, borderRadius: 52, overflow: "hidden", background: C.canvas, position: "relative", display: "flex", flexDirection: "column" }}>
      <div style={{ height: 44, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 30px", fontSize: 19, fontWeight: 600, color: C.ink }}>
        <span>9:41</span><span>✈︎</span>
      </div>
      <div style={{ position: "absolute", top: 10, left: "50%", translate: "-50% 0", width: 110, height: 30, borderRadius: 99, background: "#111" }} />
      <div style={{ textAlign: "center", fontSize: 21, fontWeight: 700, color: C.ink, padding: "8px 0 10px" }}>{title}</div>
      <div style={{ flex: 1, padding: "8px 14px", display: "flex", flexDirection: "column", gap: 10, overflow: "hidden" }}>{children}</div>
      <div style={{ height: 64, borderTop: "1px solid #E2E5DF", display: "flex", alignItems: "center", gap: 10, padding: "0 14px", background: C.white }}>
        <div style={{ width: 34, height: 34, borderRadius: 99, background: "#E6EDE2", display: "grid", placeItems: "center", fontSize: 20 }}>📷</div>
        <div style={{ flex: 1, color: C.secondary, fontSize: 19 }}>Ano ang nangyari?</div>
        <div style={{ width: 34, height: 34, borderRadius: 99, background: "#E6EDE2", display: "grid", placeItems: "center", fontSize: 20 }}>🎙️</div>
        <div style={{ width: 34, height: 34, borderRadius: 99, background: C.primary, color: C.white, display: "grid", placeItems: "center", fontSize: 18 }}>↑</div>
      </div>
    </div>
  </div>
);

/** The user's message, typed out letter by letter from `at`. */
export const Typed: React.FC<{ at: number; text: string; cps?: number }> = ({ at, text, cps = 1.4 }) => {
  const f = useCurrentFrame();
  const n = Math.max(0, Math.min(text.length, Math.floor((f - at) * cps)));
  if (f < at) return null;
  return (
    <div style={{ alignSelf: "flex-end", maxWidth: "82%", background: C.primary, color: C.white, borderRadius: 20, padding: "10px 14px", fontSize: 19, lineHeight: 1.3 }}>
      {text.slice(0, n)}{n < text.length ? "▍" : ""}
    </div>
  );
};

export const typedDone = (at: number, text: string, cps = 1.4) => at + Math.ceil(text.length / cps);

/** "Hinahanap ang tamang gabay…" while the phone routes the question. */
export const Thinking: React.FC<{ from: number; to: number }> = ({ from, to }) => {
  const f = useCurrentFrame();
  if (f < from || f >= to) return null;
  const dots = ".".repeat(1 + (Math.floor(f / 6) % 3));
  return <div style={{ fontSize: 16, color: C.secondary }}>⏳ Hinahanap ang tamang gabay{dots}</div>;
};

export const Card: React.FC<{ at: number; children: React.ReactNode; border?: string }> = ({ at, children, border }) => {
  const p = usePop(at);
  const f = useCurrentFrame();
  if (f < at) return null;
  return (
    <div style={{ opacity: Math.min(1, p * 1.3), translate: `0 ${(1 - p) * 20}px`, background: C.white, borderRadius: 18, padding: 14,
      display: "flex", flexDirection: "column", gap: 8, border: border ? `1.5px solid ${border}` : "1px solid #E2E5DF" }}>
      {children}
    </div>
  );
};

export const Line: React.FC<{ at: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ at, children, style }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at, at + 8], [0, 1], { ...clamp, easing: ease });
  return <div style={{ opacity: o, ...style }}>{children}</div>;
};
