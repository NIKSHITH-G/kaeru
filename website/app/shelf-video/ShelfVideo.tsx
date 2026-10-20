"use client";

import { useEffect, useState } from "react";
import { FileIcon, Wheel } from "../components/WheelDemo";
import "../promo/promo.css";
import "./shelf-video.css";

/**
 * A 22-second video about the shelf, rendered purely as a function of time `t` so it can be recorded
 * frame by frame (scripts/make-promo.mjs, with ?drive=1). Files from three places land on one shelf,
 * get zipped with Kaeru, and the zip is dropped into a chat.
 */
export const DURATION = 22;

const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const prog = (t: number, a: number, b: number) => clamp((t - a) / (b - a));
const ease = (p: number) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const back = (p: number) => { const c = 1.70158; return p <= 0 ? 0 : 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); };
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
const fade = (t: number, a: number, b: number, c?: number, d?: number) =>
  ease(prog(t, a, b)) * (c === undefined || d === undefined ? 1 : 1 - ease(prog(t, c, d)));
const rise = (t: number, a: number, b: number, px = 30) => `translateY(${(1 - ease(prog(t, a, b))) * px}px)`;

type Key = { t: number; x: number; y: number; down?: boolean };
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

// Desktop window (1500×860) coordinates.
const SHELF = { x: 720, y: 430 };
const SS = 1.45;  // shelf scale on video
type Kind = "photo" | "video" | "doc";
type File = { id: string; name: string; kind: Kind; from: { x: number; y: number }; grab: number; land: number };
const FILES: File[] = [
  { id: "inv", name: "Invoice.pdf", kind: "doc", from: { x: 250, y: 232 }, grab: 4.6, land: 6.25 },
  { id: "pic", name: "Beach.heic", kind: "photo", from: { x: 190, y: 640 }, grab: 7.7, land: 8.65 },
  { id: "doc", name: "Notes.docx", kind: "doc", from: { x: 1250, y: 240 }, grab: 9.2, land: 10.15 },
];
const ZIP = { made: 12.75, grab: 14.35, sent: 15.35 };
const WAND = { x: SHELF.x + 80 * SS, y: SHELF.y + 80 * SS };
const ZIP_TILE = { x: SHELF.x + 100 * SS, y: SHELF.y };
const CHAT_DROP = { x: 1230, y: 650 };

const CURSOR: Key[] = [
  { t: 3.9, x: 760, y: 820 }, { t: 4.5, ...FILES[0].from }, { t: 4.6, ...FILES[0].from, down: true },
  { t: 5.1, x: 700, y: 450, down: true },
  // The shake.
  { t: 5.2, x: 790, y: 445, down: true }, { t: 5.3, x: 630, y: 455, down: true }, { t: 5.4, x: 800, y: 448, down: true },
  { t: 5.5, x: 630, y: 452, down: true }, { t: 5.6, x: 770, y: 446, down: true }, { t: 5.75, x: 715, y: 440, down: true },
  { t: 6.15, ...SHELF, down: true }, { t: 6.25, ...SHELF }, { t: 6.9, x: 600, y: 600 },
  { t: 7.6, ...FILES[1].from }, { t: 7.7, ...FILES[1].from, down: true }, { t: 8.55, x: SHELF.x - 10, y: SHELF.y + 6, down: true },
  { t: 8.65, x: SHELF.x - 10, y: SHELF.y + 6 }, { t: 9.1, ...FILES[2].from }, { t: 9.2, ...FILES[2].from, down: true },
  { t: 10.05, x: SHELF.x + 12, y: SHELF.y - 4, down: true }, { t: 10.15, x: SHELF.x + 12, y: SHELF.y - 4 },
  { t: 11.15, ...WAND }, { t: 11.25, ...WAND, down: true }, { t: 11.35, ...WAND },
  { t: 11.95, ...ZIP_TILE }, { t: 12.55, ...ZIP_TILE, down: true }, { t: 12.65, ...ZIP_TILE },
  { t: 14.2, ...SHELF }, { t: ZIP.grab, ...SHELF, down: true }, { t: 15.25, ...CHAT_DROP, down: true },
  { t: ZIP.sent, ...CHAT_DROP }, { t: 16.2, x: 1100, y: 780 },
];

const CAPTIONS: { in: number; out: number; title: string; sub: string }[] = [
  { in: 4.0, out: 7.35, title: "Shake while dragging.", sub: "A shelf appears right under your cursor." },
  { in: 7.45, out: 10.8, title: "Collect files from anywhere.", sub: "Downloads, Desktop, Documents: one pile." },
  { in: 10.9, out: 13.75, title: "Zip them in one go.", sub: "Change everything on the shelf with ✨." },
  { in: 13.85, out: 16.95, title: "Drop it straight into a chat.", sub: "Or copy it all and paste in any folder." },
];

const ZIP_OPS = [
  { label: "ZIP", ext: "zip", hint: "archive", category: "archive" as const, result: () => "Archive.zip" },
  { label: "TAR.GZ", ext: "gz", hint: "archive", category: "archive" as const, result: () => "Archive.tar.gz" },
];

export default function ShelfVideo() {
  const [t, setT] = useState(0);

  useEffect(() => {
    if (new URLSearchParams(location.search).has("drive")) {
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
  const windowOpacity = fade(t, 3.7, 4.15, 16.9, 17.3);
  const caption = CAPTIONS.find((c) => t >= c.in && t < c.out);
  const dragged = FILES.find((f) => t >= f.grab && t < f.land);
  const zipDragging = t >= ZIP.grab && t < ZIP.sent;
  const shelfIn = 5.65;
  const shelfPop = t < shelfIn ? 0 : back(prog(t, shelfIn, shelfIn + 0.4));

  // What's on the shelf right now, in arrival order.
  const onShelf: { id: string; name: string; kind: Kind; land: number; made?: boolean }[] = FILES.filter((f) => t >= f.land);
  if (t >= ZIP.made && t < ZIP.sent) onShelf.push({ id: "zip", name: "Archive.zip", kind: "doc", land: ZIP.made, made: true });
  // Files hovering over the shelf: the pile fans apart (just before each drop).
  const hovering = FILES.some((f) => t > f.land - 0.4 && t < f.land) && t > shelfIn + 0.2;

  return (
    <div className="promo">
      <div className="promo-bg" />

      {/* 1. Hook: files scattered in three places */}
      {t < 2.7 && (
        <div className="promo-center" style={{ opacity: fade(t, 0, 0.15, 2.3, 2.6) }}>
          <h2 className="promo-hook-line" style={{ marginBottom: 70 }}>
            <span style={{ opacity: fade(t, 0.05, 0.3), display: "inline-block", transform: rise(t, 0.05, 0.35, 24) }}>Files everywhere.</span>{" "}
            <span style={{ opacity: fade(t, 1.55, 1.8), display: "inline-block", transform: rise(t, 1.55, 1.85, 24) }} className="promo-grad">One shelf.</span>
          </h2>
          <div className="sv-hook">
            {[["Downloads", "Invoice.pdf", "doc"], ["Desktop", "Beach.heic", "photo"], ["Documents", "Notes.docx", "doc"]].map(([where, name, kind], i) => {
              const d = 0.3 + i * 0.25;
              const gather = ease(prog(t, 1.6, 2.2));
              return (
                <div key={where} className="sv-mini" style={{
                  opacity: fade(t, d, d + 0.2),
                  transform: `translate(${(1 - i) * -1 * gather * 300}px, ${gather * 30}px) scale(${lerp(0.7, 1, back(prog(t, d, d + 0.35))) * lerp(1, 0.8, gather)}) rotate(${(i - 1) * 4 * (1 - gather)}deg)`,
                }}>
                  <div className="sv-mini-bar"><span /><span /><span /><b>{where}</b></div>
                  <div className="sv-mini-body"><FileIcon kind={kind as Kind} name={name} /><span>{name}</span></div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 2. Title */}
      {t >= 2.45 && t < 3.95 && (
        <div className="promo-center" style={{ opacity: fade(t, 2.5, 2.75, 3.55, 3.85), transform: `translateY(${-ease(prog(t, 3.55, 3.85)) * 30}px)` }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/shots/icon.png" alt="" className="promo-icon promo-icon-sm"
               style={{ transform: `scale(${lerp(0.8, 1, back(prog(t, 2.5, 2.9)))})` }} />
          <h1 className="promo-title" style={{ fontSize: 120, opacity: fade(t, 2.65, 2.95), transform: rise(t, 2.65, 2.95) }}>The Kaeru Shelf</h1>
          <p className="promo-sub" style={{ opacity: fade(t, 2.85, 3.15), transform: rise(t, 2.85, 3.15) }}>Shake. Collect. Change. Drop.</p>
        </div>
      )}

      {/* 3. The demo */}
      {windowOpacity > 0 && (
        <>
          <div className="promo-caption">
            {caption && (
              <div key={caption.title} style={{ opacity: fade(t, caption.in, caption.in + 0.35, caption.out - 0.3, caption.out) }}>
                <h3 style={{ transform: rise(t, caption.in, caption.in + 0.4, 20) }}>{caption.title}</h3>
                <p style={{ opacity: fade(t, caption.in + 0.25, caption.in + 0.6) }}>{caption.sub}</p>
              </div>
            )}
          </div>
          <div className="promo-window" style={{ opacity: windowOpacity, transform: `translate(-50%, 0) scale(${lerp(0.94, 1, ease(prog(t, 3.7, 4.3)))})` }}>
            <div className="demo-menubar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span className="demo-spacer" /><span>🐸</span></div>

            <FinderWindow x={70} y={90} w={380} h={260} title="Downloads">
              <DeskFile x={180} y={142} kind="doc" name="Invoice.pdf" dim={t >= FILES[0].grab && t < FILES[0].land} />
              <DeskFile x={300} y={142} kind="doc" name="Receipt.pdf" />
            </FinderWindow>
            <FinderWindow x={1060} y={90} w={380} h={260} title="Documents">
              <DeskFile x={190} y={150} kind="doc" name="Notes.docx" dim={t >= FILES[2].grab && t < FILES[2].land} />
              <DeskFile x={70} y={150} kind="doc" name="Plan.pages" />
            </FinderWindow>
            <DeskFile x={FILES[1].from.x} y={FILES[1].from.y} kind="photo" name="Beach.heic" dim={t >= FILES[1].grab && t < FILES[1].land} big />

            {/* The shake: motion marks either side of the cursor */}
            {t > 5.12 && t < 5.78 && (
              <div className="sv-shake" style={{ left: cursor.x, top: cursor.y, opacity: Math.sin(prog(t, 5.12, 5.78) * Math.PI) }}>
                <span /><span />
              </div>
            )}

            {shelfPop > 0 && (
              <Shelf t={t} items={onShelf} pop={shelfPop} hovering={hovering} draggingZip={zipDragging} />
            )}

            {/* Kaeru's picker over the shelf, choosing ZIP */}
            {t >= 11.35 && t < 12.85 && (
              <div style={{ position: "absolute", inset: 0, zIndex: 30, opacity: t < 12.65 ? clamp(prog(t, 11.35, 11.5)) : 1 - prog(t, 12.65, 12.85) }}>
                <Wheel x={SHELF.x} y={SHELF.y} mode="convert" ops={ZIP_OPS} hover={t >= 11.95 ? 0 : null} fileName="3 items"
                       scale={back(prog(t, 11.35, 11.7)) * 1.35} resize travel={prog(t, 11.95, 12.5)} />
              </div>
            )}

            {/* Toast for the zip */}
            {(() => {
              const o = fade(t, ZIP.made + 0.05, ZIP.made + 0.3, ZIP.made + 1.3, ZIP.made + 1.6);
              return o > 0 ? (
                <div className="promo-toast" style={{ opacity: o, transform: rise(t, ZIP.made + 0.05, ZIP.made + 0.35, -14) }}>
                  <span className="demo-toast-check">✓</span>Archive.zip · 3 files · 4.2 MB
                </div>
              ) : null;
            })()}

            <Chat t={t} hovering={zipDragging && t > 14.95} />

            {(dragged || zipDragging) && (
              <div className="promo-ghost" style={{ left: cursor.x, top: cursor.y }}>
                <FileIcon kind={dragged?.kind ?? "doc"} name={dragged?.name ?? "Archive.zip"} />
              </div>
            )}

            {t > 3.9 && t < 16.6 && (
              <svg className="promo-cursor" style={{ left: cursor.x, top: cursor.y, transform: `translate(-3px,-2px) scale(${cursor.down ? 0.88 : 1})`, opacity: fade(t, 3.9, 4.1, 16.3, 16.6) }}
                   width="30" height="38" viewBox="0 0 22 28" aria-hidden>
                <path d="M2 2 L2 22 L7.5 17 L11 25.5 L14.5 24 L11 15.8 L18.5 15.8 Z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
              </svg>
            )}
          </div>
        </>
      )}

      {/* 4. Features */}
      <div className="promo-center" style={{ opacity: fade(t, 17.3, 17.7, 19.4, 19.8) }}>
        <h2 className="promo-headline promo-headline-sm" style={{ transform: rise(t, 17.3, 17.8) }}>Your files, one shake away.</h2>
        <div className="sv-features">
          {["Shake to open", "Copy all", "Change with ✨", "Tuck into the edge", "Screenshot shelf", "Nothing uploaded"].map((f, i) => {
            const d = 17.6 + i * 0.12;
            return <span key={f} className="promo-chip" style={{ opacity: fade(t, d, d + 0.3), transform: `${rise(t, d, d + 0.35, 24)} scale(${lerp(0.8, 1, back(prog(t, d, d + 0.35)))})` }}>{f}</span>;
          })}
        </div>
      </div>

      {/* 5. End card */}
      <div className="promo-center" style={{ opacity: fade(t, 19.7, 20.1) }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/shots/icon.png" alt="" className="promo-icon promo-icon-sm" style={{ transform: `scale(${back(prog(t, 19.8, 20.35))})` }} />
        <h1 className="promo-title" style={{ opacity: fade(t, 20.1, 20.5), transform: rise(t, 20.1, 20.5) }}>Kaeru</h1>
        <p className="promo-sub" style={{ opacity: fade(t, 20.4, 20.8), transform: rise(t, 20.4, 20.8) }}>Free for Mac · Open source</p>
        <div className="promo-url" style={{ opacity: fade(t, 20.8, 21.2), transform: `scale(${lerp(0.9, 1, back(prog(t, 20.8, 21.25)))})` }}>
          getkaeru.vercel.app
        </div>
      </div>
    </div>
  );
}

function FinderWindow({ x, y, w, h, title, children }: { x: number; y: number; w: number; h: number; title: string; children: React.ReactNode }) {
  return (
    <div className="sv-finder" style={{ left: x, top: y, width: w, height: h }}>
      <div className="sv-finder-bar"><span /><span /><span /><b>{title}</b></div>
      <div className="sv-finder-body">{children}</div>
    </div>
  );
}

function DeskFile({ x, y, kind, name, dim = false, big = false }: { x: number; y: number; kind: Kind; name: string; dim?: boolean; big?: boolean }) {
  return (
    <div className={`promo-file ${big ? "" : "sv-small"}`} style={{ left: x, top: y, opacity: dim ? 0.35 : 1, transform: "translate(-50%, -50%)" }}>
      <FileIcon kind={kind} name={name} />
      <span className="demo-file-name">{name}</span>
    </div>
  );
}

/** The shelf as it looks in Kaeru: a glass tile with the files fanned like a little pile. */
function Shelf({ t, items, pop, hovering, draggingZip }: {
  t: number; items: { id: string; name: string; kind: Kind; land: number; made?: boolean }[]; pop: number; hovering: boolean; draggingZip: boolean;
}) {
  const top = items.slice(-3);
  const name = items.length === 0 ? "" : items.length === 1 ? items[0].name : `${items.length} Files`;
  // Haptic-style ring each time files land.
  const rings = [5.65, 6.25, 8.65, 10.15, ZIP.made].filter((at) => t > at && t < at + 0.6);
  return (
    <div className="sv-shelf" style={{ left: SHELF.x, top: SHELF.y, transform: `translate(-50%, -50%) scale(${SS * pop})`, opacity: clamp(pop * 1.4) }}>
      {rings.map((at) => {
        const p = prog(t, at, at + 0.6);
        return <span key={at} className="sv-ring" style={{ transform: `scale(${lerp(1, 1.18, ease(p))})`, opacity: (1 - p) * 0.5 }} />;
      })}
      <span className="sv-handle" />
      <span className="sv-btn sv-tl">✕</span>
      <span className="sv-btn sv-tr">⌄</span>
      {items.length === 0 ? (
        <div className="sv-empty" style={{ transform: `translateY(${hovering || t < 6.2 ? -6 : 0}px)` }}>
          <TrayIcon /><span>Drop files here</span>
        </div>
      ) : (
        <div className="sv-pile">
          {top.map((it, index) => {
            const depth = top.length - 1 - index;
            const land = back(prog(t, it.land, it.land + 0.45));
            const fan = hovering ? 1.9 : 1;
            const leaving = it.id === "zip" && draggingZip;
            return (
              <div key={it.id} className="sv-pile-item" style={{
                opacity: clamp(prog(t, it.land, it.land + 0.15)) * (leaving ? 0.35 : 1),
                transform: `translate(${depth * (index % 2 === 0 ? -8 : 8) * fan}px, ${depth * -4 + (1 - land) * -26}px) rotate(${depth * (index % 2 === 0 ? -7 : 7) * fan}deg) scale(${(1 - depth * 0.06) * lerp(1.35, 1, land)})`,
              }}>
                <FileIcon kind={it.kind} name={it.name} />
                {it.made && depth === 0 && <span className="sv-sparkle">✦</span>}
              </div>
            );
          })}
        </div>
      )}
      {items.length > 0 && (
        <div className="sv-bottom">
          <span className="sv-btn">⧉</span>
          <span className="sv-pill">{name} ›</span>
          <span className="sv-btn" style={{ background: t > 11.2 && t < 11.45 ? "#ffffff55" : undefined }}>✨</span>
        </div>
      )}
    </div>
  );
}

function TrayIcon() {
  return (
    <svg width="40" height="34" viewBox="0 0 40 34" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M4 20h9l3 5h8l3-5h9" /><path d="M4 20l5-11h22l5 11v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" /><path d="M20 3v12M15 10l5 5 5-5" />
    </svg>
  );
}

/** A generic chat app: the zip is dropped in and sent. */
function Chat({ t, hovering }: { t: number; hovering: boolean }) {
  const slide = ease(prog(t, 13.55, 14.05));
  if (slide <= 0) return null;
  const sent = t >= ZIP.sent;
  return (
    <div className="sv-chat" style={{ transform: `translateX(${(1 - slide) * 520}px)`, opacity: slide }}>
      <div className="sv-chat-head">
        <span className="sv-avatar">A</span>
        <div><b>Alex</b><small>online</small></div>
      </div>
      <div className="sv-chat-body">
        <div className="sv-msg sv-in">Can you send me today&rsquo;s files? 🙏<small>14:58</small></div>
        {sent && (
          <div className="sv-msg sv-out" style={{ opacity: fade(t, ZIP.sent, ZIP.sent + 0.2), transform: `scale(${lerp(0.85, 1, back(prog(t, ZIP.sent, ZIP.sent + 0.35)))})` }}>
            <div className="sv-attach"><FileIcon kind="doc" name="Archive.zip" /><div><b>Archive.zip</b><small>4.2 MB · ZIP</small></div></div>
            <small>15:01 <span style={{ color: t > ZIP.sent + 0.5 ? "#4aa3df" : "#9aa5a0" }}>✓✓</span></small>
          </div>
        )}
        {t > 16.2 && (
          <div className="sv-msg sv-in" style={{ opacity: fade(t, 16.2, 16.4), transform: rise(t, 16.2, 16.45, 12) }}>Got them, thanks!<small>15:01</small></div>
        )}
        {hovering && <div className="sv-drop">Drop to send</div>}
      </div>
      <div className="sv-chat-input"><span>Message</span></div>
    </div>
  );
}

