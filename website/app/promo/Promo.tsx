"use client";

import { useEffect, useState } from "react";
import { FileIcon, OPS, R_MID, R_OUT, RIM, Wheel, type Mode } from "../components/WheelDemo";
import "./promo.css";

/**
 * A 25-second promo, rendered purely as a function of time `t` so it can be captured frame by frame.
 * Opened normally it plays in a loop; with ?drive=1 a recorder steps time through DOM attributes.
 */
export const DURATION = 25;

const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const prog = (t: number, a: number, b: number) => clamp((t - a) / (b - a));
const ease = (p: number) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const back = (p: number) => { const c = 1.70158; return p <= 0 ? 0 : 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); };
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
/** Fade in over [a, b], out over [c, d]. */
const fade = (t: number, a: number, b: number, c?: number, d?: number) =>
  ease(prog(t, a, b)) * (c === undefined || d === undefined ? 1 : 1 - ease(prog(t, c, d)));
const rise = (t: number, a: number, b: number, px = 30) => `translateY(${(1 - ease(prog(t, a, b))) * px}px)`;

type Key = { t: number; x: number; y: number; down?: boolean };
/** Cursor position between keyframes, eased. */
function along(keys: Key[], t: number) {
  if (t <= keys[0].t) return keys[0];
  for (let i = 1; i < keys.length; i++) {
    if (t <= keys[i].t) {
      const a = keys[i - 1], b = keys[i], p = ease(prog(t, a.t, b.t));
      return { t, x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p), down: a.down };
    }
  }
  return keys[keys.length - 1];
}

/** The opening hook: a file card's format badge flips through these, 0.19s each. */
const HOOK: [string, string][] = [
  ["HEIC", "#A855F7"], ["JPG", "#A855F7"], ["PNG", "#A855F7"], ["PDF", "#EF4444"], ["MP4", "#F43F5E"],
  ["MP3", "#F59E0B"], ["DOCX", "#3B82F6"], ["EPUB", "#3B82F6"], ["XLSX", "#10B981"],
];

// Desktop window (1500×860) coordinates. The wheel is drawn larger than on the site so it reads on video.
const C = { x: 750, y: 450 };
const WS = 1.35;
const F = { heic: { x: 260, y: 300 }, mov: { x: 260, y: 600 }, doc: { x: 1240, y: 300 } };
const tile = (i: number, n: number) => {
  const a = (i + 0.5) * (2 * Math.PI) / n;
  return { x: C.x + Math.sin(a) * R_MID * WS, y: C.y - Math.cos(a) * R_MID * WS };
};

const CURSOR: Key[] = [
  { t: 4.9, x: 750, y: 830 }, { t: 5.4, x: 750, y: 830 }, { t: 6.0, x: F.heic.x, y: F.heic.y },
  { t: 6.1, x: F.heic.x, y: F.heic.y, down: true }, { t: 6.8, ...C, down: true }, { t: 7.3, ...C, down: true },
  { t: 7.9, ...tile(0, 8), down: true }, { t: 8.6, ...tile(0, 8) }, { t: 9.3, x: 900, y: 720 },
  { t: 10.3, x: 900, y: 720 }, { t: 10.9, x: F.mov.x, y: F.mov.y }, { t: 11.0, x: F.mov.x, y: F.mov.y, down: true },
  { t: 11.6, ...C, down: true }, { t: 12.1, ...C, down: true }, { t: 12.6, ...tile(2, 7), down: true },
  { t: 13.1, ...tile(2, 7) }, { t: 13.7, x: 1000, y: 700 },
  { t: 14.2, x: 1000, y: 700 }, { t: 14.7, x: F.doc.x, y: F.doc.y }, { t: 14.8, x: F.doc.x, y: F.doc.y, down: true },
  { t: 15.3, ...C, down: true }, { t: 15.6, ...C, down: true }, { t: 16.0, ...tile(0, 7), down: true },
  { t: 16.4, ...tile(0, 7) }, { t: 17.0, x: 1100, y: 760 },
];

type Beat = {
  file: "heic" | "mov" | "doc"; kind: "photo" | "video" | "doc"; name: string; mode: Mode; key: string; keyName: string;
  grab: number; wheelIn: number; hoverAt: number; hover: number; drop: number; toast: string; result?: string;
  caption: [string, string]; captionIn: number; captionOut: number;
};
const BEATS: Beat[] = [
  { file: "heic", kind: "photo", name: "Vacation.heic", mode: "convert", key: "⇧", keyName: "Shift", grab: 6.05, wheelIn: 6.9,
    hoverAt: 7.85, hover: 0, drop: 8.6, toast: "Vacation.jpg", result: "Vacation.jpg",
    caption: ["Drag a file. Hold ⇧. Drop.", "Convert to any format, right where you are."], captionIn: 5.0, captionOut: 10.2 },
  { file: "mov", kind: "video", name: "Interview.mov", mode: "tools", key: "⌘", keyName: "Command", grab: 10.95, wheelIn: 11.7,
    hoverAt: 12.55, hover: 2, drop: 13.1, toast: "Interview (compressed).mp4 · 210 MB → 38 MB (−82%)", result: "Interview (compressed).mp4",
    caption: ["Hold ⌘ for tools.", "Trim, crop, compress, remove backgrounds."], captionIn: 10.3, captionOut: 14.1 },
  { file: "doc", kind: "doc", name: "Thesis.docx", mode: "actions", key: "⌃", keyName: "Control", grab: 14.75, wheelIn: 15.35,
    hoverAt: 15.95, hover: 0, drop: 16.4, toast: "Sent with AirDrop",
    caption: ["Hold ⌃ for actions.", "AirDrop, float, copy path, open Terminal."], captionIn: 14.2, captionOut: 17.4 },
];

export default function Promo() {
  const [t, setT] = useState(0);

  useEffect(() => {
    const driven = new URLSearchParams(location.search).has("drive");
    if (driven) {
      // The recorder sets <html data-promo-t> and fires "promo-time"; we answer with data-promo-frame once
      // that frame is painted. (DOM-based, so it works from an isolated automation context.)
      const root = document.documentElement;
      const onTime = () => {
        const v = Number(root.dataset.promoT);
        setT(v);
        requestAnimationFrame(() => requestAnimationFrame(() => { root.dataset.promoFrame = String(v); }));
      };
      document.addEventListener("promo-time", onTime);
      document.fonts.ready.then(() => { root.dataset.promoReady = "1"; });
      return () => document.removeEventListener("promo-time", onTime);
    }
    let raf = 0;
    const start = performance.now();
    const loop = (now: number) => { setT(((now - start) / 1000) % DURATION); raf = requestAnimationFrame(loop); };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  const cursor = along(CURSOR, t);
  const windowOpacity = fade(t, 4.8, 5.3, 17.3, 17.7);
  const windowScale = lerp(0.94, 1, ease(prog(t, 4.8, 5.4)));
  const beat = BEATS.find((b) => t >= b.grab && t < b.drop);
  const caption = BEATS.find((b) => t >= b.captionIn && t < b.captionOut);

  return (
    <div className="promo">
      <div className="promo-bg" />

      {/* 1. Hook: one file card flipping through formats */}
      {t < 2.4 && (
        <div className="promo-center" style={{ opacity: fade(t, 0, 0.15, 1.95, 2.18) }}>
          <h2 className="promo-hook-line">
            {/* "Any file." sits centred alone, then slides left as "Any format." arrives. */}
            <span style={{ opacity: fade(t, 0.05, 0.3), display: "inline-block",
                           transform: `${rise(t, 0.05, 0.35, 24)} translateX(${(1 - ease(prog(t, 0.72, 1.0))) * 236}px)` }}>Any file.</span>{" "}
            <span style={{ opacity: fade(t, 0.78, 1.02), transform: rise(t, 0.78, 1.08, 24), display: "inline-block" }} className="promo-grad">Any format.</span>
          </h2>
          {(() => {
            const slot = Math.min(HOOK.length - 1, Math.floor(t / 0.19));
            const local = (t - slot * 0.19) / 0.19;
            const morph = ease(prog(t, 1.7, 2.25));
            const [label, color] = HOOK[slot];
            return (
              <div className="promo-hook-stage">
                <div className="promo-hook-card" style={{
                  transform: `scale(${lerp(1, 0.62, morph)}) scaleX(${1 + Math.sin(morph * Math.PI) * 0.12})`,
                  borderRadius: lerp(26, 60, morph), opacity: 1 - morph,
                }}>
                  <span className="promo-hook-fold" />
                  <span className="promo-hook-badge" style={{
                    background: color,
                    transform: `perspective(600px) rotateX(${(1 - ease(clamp(local / 0.45))) * 80}deg)`,
                  }}>{label}</span>
                </div>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/shots/icon.png" alt="" className="promo-hook-icon"
                     style={{ opacity: morph, transform: `scale(${lerp(0.7, 1, back(prog(t, 1.8, 2.3)))})` }} />
                {[0, 0.18].map((d) => {
                  const p = prog(t, 1.8 + d, 2.6 + d);
                  return p > 0 && p < 1 ? (
                    <span key={d} className="promo-ripple" style={{ transform: `scale(${lerp(0.6, 2.4, ease(p))})`, opacity: (1 - p) * 0.6 }} />
                  ) : null;
                })}
              </div>
            );
          })()}
        </div>
      )}

      {/* 2. Name, landing letter by letter */}
      {t >= 2.08 && t < 3.6 && (
        <div className="promo-center" style={{ opacity: 1 - ease(prog(t, 3.25, 3.5)), transform: `translateY(${-ease(prog(t, 3.25, 3.5)) * 30}px)` }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/shots/icon.png" alt="" className="promo-icon promo-icon-sm"
               style={{ opacity: fade(t, 2.1, 2.3), transform: `translateY(${lerp(60, 0, ease(prog(t, 2.1, 2.45)))}px) scale(${lerp(0.85, 1, back(prog(t, 2.1, 2.45)))})` }} />
          <p className="promo-kana maru" style={{ opacity: fade(t, 2.45, 2.75) }}>かえる</p>
          <h1 className="promo-title promo-title-letters">
            {"Kaeru".split("").map((ch, i) => {
              const p = prog(t, 2.25 + i * 0.06, 2.6 + i * 0.06);
              return <span key={i} style={{ opacity: clamp(p * 2), transform: `translateY(${(1 - back(p)) * -60}px)` }}>{ch}</span>;
            })}
          </h1>
          <p className="promo-sub" style={{ opacity: fade(t, 2.7, 3.0), transform: rise(t, 2.7, 3.0) }}>
            Japanese for “to change”, and “frog”.
          </p>
        </div>
      )}

      {/* 3. Headline */}
      <div className="promo-center" style={{ opacity: fade(t, 3.35, 3.55, 4.5, 4.85) }}>
        <h2 className="promo-headline">
          <span style={{ opacity: fade(t, 3.4, 3.7), transform: rise(t, 3.4, 3.7, 40), display: "inline-block" }}>Change any file.</span>
          <br />
          <span className="promo-grad" style={{ opacity: fade(t, 3.6, 3.95), transform: rise(t, 3.6, 3.95, 40), display: "inline-block" }}>
            Without opening anything.
          </span>
        </h2>
      </div>

      {/* 3–5. Desktop demo */}
      {windowOpacity > 0 && (
        <>
          <div className="promo-caption">
            {caption && (
              <div key={caption.caption[0]} style={{ opacity: fade(t, caption.captionIn, caption.captionIn + 0.35, caption.captionOut - 0.3, caption.captionOut) }}>
                <h3 style={{ transform: rise(t, caption.captionIn, caption.captionIn + 0.4, 20) }}>{caption.caption[0]}</h3>
                <p style={{ opacity: fade(t, caption.captionIn + 0.25, caption.captionIn + 0.6) }}>{caption.caption[1]}</p>
              </div>
            )}
          </div>
          <div className="promo-window" style={{ opacity: windowOpacity, transform: `translate(-50%, 0) scale(${windowScale})` }}>
            <div className="demo-menubar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span className="demo-spacer" /><span>🐸</span></div>

            {(Object.keys(F) as (keyof typeof F)[]).map((k) => {
              const b = BEATS.find((x) => x.file === k)!;
              return <PromoFile key={k} {...F[k]} kind={b.kind} name={b.name} dim={beat?.file === k} />;
            })}
            {BEATS.filter((b) => b.result && t >= b.drop + 0.05).map((b) => {
              const p = back(prog(t, b.drop + 0.05, b.drop + 0.45));
              const pos = { x: F[b.file].x + 240, y: F[b.file].y };
              return <PromoFile key={b.result} {...pos} kind={b.kind} name={b.result!} scale={p} />;
            })}

            {beat && (
              <div className="promo-ghost" style={{ left: cursor.x, top: cursor.y }}>
                <FileIcon kind={beat.kind} name={beat.name} />
              </div>
            )}

            {BEATS.map((b) => {
              if (t < b.wheelIn || t > b.drop + 0.2) return null;
              const pop = t < b.drop ? back(prog(t, b.wheelIn, b.wheelIn + 0.32)) : 1 - ease(prog(t, b.drop, b.drop + 0.2)) * 0.15;
              const opacity = t < b.drop ? clamp(prog(t, b.wheelIn, b.wheelIn + 0.12)) : 1 - prog(t, b.drop, b.drop + 0.2);
              const ops = OPS[b.kind][b.mode];
              return (
                <div key={b.name} style={{ opacity }}>
                  <Wheel x={C.x} y={C.y} mode={b.mode} ops={ops} hover={t >= b.hoverAt ? b.hover : null} fileName={b.name} scale={pop * WS} resize />
                  <div className="promo-key" style={{ left: C.x, top: C.y - (R_OUT + RIM) * WS - 70, transform: `translateX(-50%) scale(${back(prog(t, b.wheelIn - 0.08, b.wheelIn + 0.2))})` }}>
                    <kbd>{b.key}</kbd>{b.keyName}
                  </div>
                </div>
              );
            })}

            {BEATS.map((b) => {
              const o = fade(t, b.drop + 0.05, b.drop + 0.3, b.drop + 1.2, b.drop + 1.5);
              return o > 0 ? (
                <div key={b.toast} className="promo-toast" style={{ opacity: o, transform: rise(t, b.drop + 0.05, b.drop + 0.35, -14) }}>
                  <span className="demo-toast-check">✓</span>{b.toast}
                </div>
              ) : null;
            })}

            {t > 5.2 && t < 17.2 && (
              <svg className="promo-cursor" style={{ left: cursor.x, top: cursor.y, transform: `translate(-3px,-2px) scale(${cursor.down ? 0.88 : 1})` }}
                   width="30" height="38" viewBox="0 0 22 28" aria-hidden>
                <path d="M2 2 L2 22 L7.5 17 L11 25.5 L14.5 24 L11 15.8 L18.5 15.8 Z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
              </svg>
            )}
          </div>
        </>
      )}

      {/* 6. Stats */}
      <div className="promo-center" style={{ opacity: fade(t, 17.7, 18.1, 20.3, 20.7) }}>
        <h2 className="promo-headline promo-headline-sm" style={{ transform: rise(t, 17.7, 18.2) }}>Everything stays on your Mac.</h2>
        <div className="promo-stats">
          {[
            { n: Math.round(351 * ease(prog(t, 18.0, 19.1))).toString(), l: "conversions", d: 18.0 },
            { n: "30+", l: "tools", d: 18.25 },
            { n: "0", l: "uploads", d: 18.5 },
          ].map((s) => (
            <div key={s.l} style={{ opacity: fade(t, s.d, s.d + 0.35), transform: rise(t, s.d, s.d + 0.4, 24) }}>
              <b>{s.n}</b><span>{s.l}</span>
            </div>
          ))}
        </div>
        <div className="promo-marquee" style={{ opacity: fade(t, 18.6, 19.0) }}>
          <div style={{ transform: `translateX(${-(t - 17.7) * 90}px)` }}>
            {"HEIC JPG PNG WebP AVIF PDF MP4 MOV GIF MP3 WAV DOCX EPUB PPTX XLSX CSV ZIP SRT HEIC JPG PNG WebP AVIF PDF MP4 MOV GIF MP3".split(" ").map((f, i) => (
              <span key={i} className="promo-chip">{f}</span>
            ))}
          </div>
        </div>
      </div>

      {/* 7. End card */}
      <div className="promo-center" style={{ opacity: fade(t, 20.6, 21.0) }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/shots/icon.png" alt="" className="promo-icon promo-icon-sm" style={{ transform: `scale(${back(prog(t, 20.7, 21.25))})` }} />
        <h1 className="promo-title" style={{ opacity: fade(t, 21.0, 21.4), transform: rise(t, 21.0, 21.4) }}>Kaeru</h1>
        <p className="promo-sub" style={{ opacity: fade(t, 21.3, 21.7), transform: rise(t, 21.3, 21.7) }}>Free for Mac · Open source</p>
        <div className="promo-url" style={{ opacity: fade(t, 21.7, 22.1), transform: `scale(${lerp(0.9, 1, back(prog(t, 21.7, 22.15)))})` }}>
          getkaeru.vercel.app
        </div>
        <p className="promo-small" style={{ opacity: fade(t, 22.1, 22.5) }}>github.com/NIKSHITH-G/kaeru</p>
      </div>
    </div>
  );
}

function PromoFile({ x, y, kind, name, dim = false, scale = 1 }: {
  x: number; y: number; kind: "photo" | "video" | "doc"; name: string; dim?: boolean; scale?: number;
}) {
  return (
    <div className="promo-file" style={{ left: x, top: y, opacity: dim ? 0.35 : 1, transform: `translate(-50%, -50%) scale(${scale})` }}>
      <FileIcon kind={kind} name={name} />
      <span className="demo-file-name">{name}</span>
    </div>
  );
}
