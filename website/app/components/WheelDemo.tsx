"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { Archive, AudioWaveform, Braces, Film, File, FileText, Image as ImageIcon, Presentation, RefreshCcw, Sheet, Wrench, Zap } from "lucide-react";
import { COLORS, type Category } from "../site";

export type Mode = "convert" | "tools" | "actions";
type Op = { label: string; hint?: string; ext?: string; category: Category; result: (name: string) => string };

type DemoFile = { id: string; name: string; kind: "photo" | "video" | "doc"; x: number; y: number; fresh?: boolean };

const base = (n: string) => n.replace(/\.[^.]+$/, "");
const convert = (ext: string, category: Category, hint?: string): Op => ({
  label: ext.toUpperCase(), ext: ext.toLowerCase(), hint, category, result: (n) => `${base(n)}.${ext.toLowerCase()}`,
});
const tool = (label: string, result: (n: string) => string): Op => ({ label, category: "tool", result });
const action = (label: string, message: string): Op => ({ label, category: "action", result: () => message });

const ACTIONS: Op[] = [
  action("AirDrop", "Sent with AirDrop"), action("Float", "Floating above your windows"), action("Copy", "Copied. Paste in Finder"),
  action("Copy Path", "Copied path"), action("Move To…", "Moved to Documents"), action("Terminal", "Opened Terminal here"),
  action("Reveal", "Shown in Finder"),
];

export const OPS: Record<DemoFile["kind"], Record<Mode, Op[]>> = {
  photo: {
    convert: [convert("jpg", "image", "Universal"), convert("png", "image", "Lossless"), convert("webp", "image", "Web"),
      convert("avif", "image", "Smallest"), convert("pdf", "pdf", "Document"), convert("tiff", "image"),
      convert("gif", "image"), convert("ico", "image")],
    tools: [tool("Crop", (n) => `${base(n)} (cropped).heic`), tool("Remove BG", (n) => `${base(n)} (no background).png`),
      tool("Compress", (n) => `${base(n)} (compressed).heic · 4.2 MB → 1.1 MB (−74%)`), tool("Half Size", (n) => `${base(n)} (half).heic`),
      tool("Rotate", (n) => `${base(n)} (rotated).heic`), tool("Extract Text", (n) => `${base(n)}.txt`)],
    actions: ACTIONS,
  },
  video: {
    convert: [convert("mp4", "video", "Universal"), convert("gif", "image", "Animated"), convert("webm", "video", "Web"),
      convert("mkv", "video"), convert("mp3", "audio", "Audio"), convert("m4a", "audio", "Audio"), convert("wav", "audio", "Lossless")],
    tools: [tool("Trim", (n) => `${base(n)} (trimmed).mov`), tool("Crop", (n) => `${base(n)} (cropped).mp4`),
      tool("Compress", (n) => `${base(n)} (compressed).mp4 · 210 MB → 38 MB (−82%)`), tool("720p", (n) => `${base(n)} (720p).mp4`),
      tool("Mute", (n) => `${base(n)} (muted).mov`), tool("2× Speed", (n) => `${base(n)} (2x).mp4`), tool("Snapshot", (n) => `${base(n)} (frame).jpg`)],
    actions: ACTIONS,
  },
  doc: {
    convert: [convert("pdf", "pdf", "Document"), convert("md", "document", "Text"), convert("epub", "document", "E-book"),
      convert("html", "document"), convert("rtf", "document"), convert("odt", "document"), convert("txt", "document")],
    tools: [tool("Word Count", () => "2,481 words · 14,902 characters")],
    actions: ACTIONS,
  },
};

const MODE_KEYS: Record<Mode, string> = { convert: "⇧", tools: "⌘", actions: "⌃" };
const MODE_COLORS: Record<Mode, string> = { convert: COLORS.brand, tools: COLORS.tool, actions: COLORS.action };

const INITIAL: DemoFile[] = [
  { id: "a", name: "Vacation.heic", kind: "photo", x: 0.18, y: 0.3 },
  { id: "b", name: "Interview.mov", kind: "video", x: 0.18, y: 0.72 },
  { id: "c", name: "Thesis.docx", kind: "doc", x: 0.82, y: 0.3 },
];

// Same proportions as the app's sumi-e picker: ink pools on a disc of paper.
export const R_IN = 56, R_OUT = 144, R_MID = 100, RIM = 10, POOL = 32;

function modeFromKey(e: KeyboardEvent): Mode | null {
  if (e.key === "Shift") return "convert";
  if (e.key === "Meta") return "tools";
  if (e.key === "Control") return "actions";
  return null;
}

export default function WheelDemo() {
  const stage = useRef<HTMLDivElement>(null);
  const [files, setFiles] = useState<DemoFile[]>(INITIAL);
  const [drag, setDrag] = useState<{ file: DemoFile; x: number; y: number } | null>(null);
  const [wheel, setWheel] = useState<{ x: number; y: number; mode: Mode } | null>(null);
  const [hover, setHover] = useState<number | null>(null);
  const [toast, setToast] = useState<{ text: string; ok: boolean } | null>(null);
  const [tried, setTried] = useState(false);
  // The replay runs until the visitor touches the demo; then it's theirs.
  const [auto, setAuto] = useState(true);
  const [cursor, setCursor] = useState<{ x: number; y: number; down: boolean } | null>(null);
  const [pressed, setPressed] = useState<Mode | null>(null);
  const [scale, setScale] = useState(1);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const still = useRef<{ timer: ReturnType<typeof setTimeout> | null; x: number; y: number }>({ timer: null, x: 0, y: 0 });

  const ops = drag && wheel ? OPS[drag.file.kind][wheel.mode] : [];

  const local = useCallback((clientX: number, clientY: number) => {
    const r = stage.current!.getBoundingClientRect();
    return { x: clientX - r.left, y: clientY - r.top };
  }, []);

  const sliceAt = useCallback((x: number, y: number, w: { x: number; y: number }, count: number) => {
    const dx = (x - w.x) / scale, dy = (y - w.y) / scale, r = Math.hypot(dx, dy);
    if (r < R_IN) return -1;
    if (r > R_OUT + 20 || count === 0) return null;
    let theta = Math.atan2(dx, -dy);           // clockwise from 12 o'clock
    if (theta < 0) theta += 2 * Math.PI;
    return Math.min(Math.floor(theta / ((2 * Math.PI) / count)), count - 1);
  }, [scale]);

  // Shrink the wheel on narrow screens so it always fits the stage.
  useEffect(() => {
    const fit = () => {
      const w = stage.current?.clientWidth ?? 1000;
      setScale(Math.min(1, (w - 16) / ((R_OUT + RIM + 12) * 2)));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  // The latest drag position, readable from timers and key handlers without stale closures.
  const dragRef = useRef(drag);
  useEffect(() => { dragRef.current = drag; }, [drag]);

  const openWheel = useCallback((mode: Mode) => {
    const d = dragRef.current;
    if (!d) return;
    setWheel((w) => (w ? { ...w, mode } : { x: d.x, y: d.y, mode }));
  }, []);

  // Keyboard: the same keys as the app, pressed while dragging.
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      const mode = modeFromKey(e);
      if (mode && drag && !auto) { e.preventDefault(); openWheel(mode); setPressed(mode); }
      if (e.key === "Escape") { setWheel(null); setDrag(null); }
    };
    window.addEventListener("keydown", down);
    return () => window.removeEventListener("keydown", down);
  }, [drag, openWheel, auto]);

  /** Drops `file` on `op`: shows the result and, for conversions, puts the new file on the desktop. */
  const complete = useCallback((file: DemoFile, op: Op, byVisitor: boolean) => {
    const text = op.result(file.name);
    setToast({ text, ok: true });
    if (byVisitor) setTried(true);
    if (op.category === "action" || text.includes("words")) return;
    const name = text.split(" · ")[0];
    const kind: DemoFile["kind"] = /\.(mp4|mov|mkv|webm)$/.test(name) ? "video"
      : /\.(jpg|png|webp|avif|tiff|gif|ico|heic)$/.test(name) ? "photo" : "doc";
    setFiles((fs) => [...fs.slice(-5), {
      id: Math.random().toString(36).slice(2), name, kind, fresh: true,
      x: Math.min(0.82, Math.max(0.18, file.x + 0.2 * (file.x > 0.5 ? -1 : 1))),
      y: Math.min(0.78, file.y + 0.12 * fs.filter((f) => f.fresh).length + 0.02),
    }]);
  }, []);

  /** Ends the replay and clears its leftovers; only called while the replay is running. */
  const stopReplay = useCallback(() => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
    setAuto(false);
    setCursor(null); setWheel(null); setHover(null); setPressed(null); setToast(null); setFiles(INITIAL);
  }, []);

  // The replay: a cursor picks up the photo, presses ⇧, and drops it on JPG. Loops until touched.
  useEffect(() => {
    if (!auto || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const at = (ms: number, fn: () => void) => timers.current.push(setTimeout(fn, ms));
    const run = () => {
      const el = stage.current;
      if (!el) return;
      const W = el.clientWidth, H = el.clientHeight;
      const file = INITIAL[0];
      const start = { x: W * 0.55, y: H * 0.95 }, pick = { x: file.x * W, y: file.y * H };
      const centre = { x: W * 0.5, y: H * 0.5 };
      const jpg = { x: centre.x + 4, y: centre.y - R_MID * scale };
      setFiles(INITIAL); setToast(null);
      setCursor({ ...start, down: false });
      at(250, () => setCursor({ ...pick, down: false }));
      at(1150, () => { setCursor({ ...pick, down: true }); setDrag({ file, ...pick }); });
      at(1350, () => { setCursor({ ...centre, down: true }); setDrag({ file, ...centre }); });
      at(2250, () => { setPressed("convert"); setWheel({ ...centre, mode: "convert" }); });
      at(2850, () => { setCursor({ ...jpg, down: true }); setDrag({ file, ...jpg }); });
      at(3500, () => setHover(0));
      at(4400, () => {
        complete(file, OPS.photo.convert[0], false);
        setCursor({ ...jpg, down: false }); setPressed(null); setDrag(null); setWheel(null); setHover(null);
      });
      at(5000, () => setCursor(null));
      at(8000, run);
    };
    at(900, run);
    const pending = timers.current;
    return () => { pending.forEach(clearTimeout); };
  }, [auto, scale, complete]);

  const onPointerDown = (file: DemoFile) => (e: React.PointerEvent) => {
    e.preventDefault();
    if (auto) stopReplay();
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    const p = local(e.clientX, e.clientY);
    const next = { file, ...p };
    dragRef.current = next;
    setDrag(next);
    setToast(null);
    armStillTimer(p.x, p.y);
  };

  // Touch screens have no modifier keys: pausing mid-drag opens the Convert wheel.
  const armStillTimer = (x: number, y: number) => {
    if (still.current.timer) clearTimeout(still.current.timer);
    still.current = { x, y, timer: setTimeout(() => openWheel("convert"), 650) };
  };

  const onPointerMove = (e: React.PointerEvent) => {
    if (!drag || auto) return;
    const p = local(e.clientX, e.clientY);
    const next = { ...drag, ...p };
    dragRef.current = next;
    setDrag(next);
    if (wheel) {
      setHover(sliceAt(p.x, p.y, wheel, ops.length));
    } else if (Math.hypot(p.x - still.current.x, p.y - still.current.y) > 6) {
      armStillTimer(p.x, p.y);
    }
  };

  const onPointerUp = () => {
    if (auto) return;
    if (still.current.timer) clearTimeout(still.current.timer);
    if (drag && wheel && hover !== null && hover >= 0 && ops[hover]) complete(drag.file, ops[hover], true);
    setDrag(null);
    setWheel(null);
    setHover(null);
    setPressed(null);
  };

  return (
    <div className="demo">
      <div
        ref={stage}
        className={`demo-stage ${auto ? "is-auto" : ""}`}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        <div className="demo-menubar">
          <span className="demo-apple"></span><b>Finder</b><span>File</span><span>Edit</span><span>View</span>
          <span className="demo-spacer" />
          <span className="demo-frog" aria-hidden>🐸</span>
        </div>

        {files.map((f) => (
          <button
            key={f.id}
            className={`demo-file ${drag?.file.id === f.id ? "is-dragging" : ""} ${f.fresh ? "is-fresh" : ""}`}
            style={{ left: `${f.x * 100}%`, top: `${f.y * 100}%` }}
            onPointerDown={onPointerDown(f)}
            aria-label={`Drag ${f.name}`}
          >
            <FileIcon kind={f.kind} name={f.name} />
            <span className="demo-file-name">{f.name}</span>
          </button>
        ))}

        {drag && (
          <div className="demo-ghost" style={{ left: drag.x, top: drag.y }}>
            <FileIcon kind={drag.file.kind} name={drag.file.name} />
          </div>
        )}

        {drag && wheel && (
          <Wheel x={wheel.x} y={wheel.y} mode={wheel.mode} ops={ops} hover={hover} fileName={drag.file.name} scale={scale} />
        )}

        {pressed && wheel && (
          <div className="demo-key" style={{ left: wheel.x, top: wheel.y - (R_OUT + RIM) * scale - 46 }}>
            <kbd>{MODE_KEYS[pressed]}</kbd> {pressed === "convert" ? "Shift" : pressed === "tools" ? "Command" : "Control"}
          </div>
        )}

        {cursor && (
          <svg className={`demo-cursor ${cursor.down ? "is-down" : ""}`} style={{ left: cursor.x, top: cursor.y }}
               width="22" height="28" viewBox="0 0 22 28" aria-hidden>
            <path d="M2 2 L2 22 L7.5 17 L11 25.5 L14.5 24 L11 15.8 L18.5 15.8 Z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
          </svg>
        )}

        {auto && !wheel && (
          <button className="demo-hint is-replay" onClick={stopReplay}>
            <b>Watching a replay.</b> Grab any file to try it yourself
          </button>
        )}

        {!auto && !drag && !tried && (
          <div className="demo-hint">
            <b>Try it:</b> drag a file, then press <kbd>⇧</kbd> <kbd>⌘</kbd> or <kbd>⌃</kbd>
            <span className="demo-hint-touch"> (on touch, pause while dragging)</span>
          </div>
        )}

        {toast && (
          <div className={`demo-toast ${toast.ok ? "" : "is-error"}`} key={toast.text}>
            <span className="demo-toast-check">✓</span>
            <span>{toast.text}</span>
          </div>
        )}
      </div>
      <p className="demo-caption">
        A live, in-browser demo of Kaeru&rsquo;s wheel. On your Mac it works on real files, from anywhere.
      </p>
    </div>
  );
}

const HINTS: Record<string, string> = {
  jpg: "universal", png: "lossless", webp: "small, web", avif: "smallest", pdf: "document", tiff: "print quality",
  gif: "animated", ico: "Windows icon", mp4: "universal", webm: "web video", mkv: "any player", mp3: "universal",
  m4a: "Apple audio", wav: "lossless", md: "plain text", epub: "e-book", html: "web page", rtf: "rich text",
  odt: "LibreOffice", txt: "just text",
};

const CATEGORY_ICONS: Record<Category, typeof File> = {
  image: ImageIcon, video: Film, audio: AudioWaveform, pdf: FileText, document: FileText, spreadsheet: Sheet,
  slides: Presentation, data: Braces, archive: Archive, tool: Wrench, action: Zap, brand: RefreshCcw,
};
const MODE_ICONS: Record<Mode, typeof File> = { convert: RefreshCcw, tools: Wrench, actions: Zap };

/** Deterministic wobble for hand-made edges, matching wobble() in WheelView.swift. */
const wobble = (x: number, seed: number) =>
  Math.sin(x * 3.1 + seed) * 0.5 + Math.sin(x * 7.3 + seed * 1.7) * 0.3 + Math.sin(x * 13.7 + seed * 0.3) * 0.2;

/** An irregular pool of ink around (cx, cy). */
function poolPath(cx: number, cy: number, r: number, seed: number) {
  let d = "";
  for (let k = 0; k <= 56; k++) {
    const t = (k / 56) * 2 * Math.PI, rr = r * (1 + wobble(t * 1.3, seed) * 0.2);
    d += `${k ? "L" : "M"}${(cx + rr * Math.cos(t)).toFixed(1)},${(cy + rr * Math.sin(t)).toFixed(1)}`;
  }
  return d + "Z";
}

/** Rounded so the server and the browser render identical numbers (no hydration mismatch). */
const r2 = (v: number) => Math.round(v * 100) / 100;

/** The centre of choice `i` of `n`, clockwise from 12 o'clock. */
const spot = (i: number, n: number) => {
  const a = ((i + 0.5) * 2 * Math.PI) / n;
  return { x: r2(Math.sin(a) * R_MID), y: r2(-Math.cos(a) * R_MID), a };
};

type Ink = { angle: number; radius: number; color: string; trail: { x: number; y: number }[]; fills: number[]; wave: number };

/** You are a drop of ink: it flows out of the file toward the aimed choice, glides around the disc
 *  between choices, then soaks in while that pool fills with colour from the bottom. Mirrors tick()
 *  in WheelView.swift. */
function useInk(hover: number | null, colors: string[], still: boolean, travel?: number): Ink {
  const n = colors.length;
  const [ink, setInk] = useState<Ink>({ angle: 0, radius: 0, color: colors[0] ?? "#888", trail: [], fills: colors.map(() => 0), wave: 0 });
  const state = useRef(ink);
  const target = useRef(hover);
  useEffect(() => { target.current = hover; }, [hover]);

  // The end state: the drop has arrived and its pool is full.
  const settledInk = (): Ink => {
    const h = hover !== null && hover >= 0 && hover < n ? hover : null;
    return { angle: h !== null ? spot(h, n).a : 0, radius: h !== null ? R_MID : 0, color: h !== null ? colors[h] : colors[0] ?? "#888",
             trail: [], fills: colors.map((_, i) => (i === h ? 1 : 0)), wave: 1.3 };
  };

  useEffect(() => {
    if (still || travel !== undefined) return;
    // Reduced motion: jump straight to the end state.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const frame = requestAnimationFrame(() => { state.current = settledInk(); setInk(state.current); });
      return () => cancelAnimationFrame(frame);
    }
    let frame = 0, last = performance.now();
    const closeness = (s: Ink, i: number) => {
      const p = spot(i, n), hx = Math.sin(s.angle) * s.radius, hy = -Math.cos(s.angle) * s.radius;
      const t = Math.max(0, Math.min(1, 1 - (Math.hypot(hx - p.x, hy - p.y) - POOL * 0.25) / (POOL * 1.5)));
      return t * t * (3 - 2 * t);
    };
    const step = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const s = { ...state.current, trail: [...state.current.trail], fills: [...state.current.fills] };
      if (s.fills.length !== n) s.fills = colors.map(() => 0);
      const k = 1 - Math.exp(-dt * 13), h = target.current;
      let ta = s.angle, tr = s.radius;
      if (h !== null && h >= 0 && h < n) { ta = spot(h, n).a; tr = R_MID; s.color = colors[h]; }
      else if (h === -1) tr = 0;
      if (s.radius < R_IN * 0.6) s.angle = ta;
      let da = (ta - s.angle) % (2 * Math.PI);
      if (da > Math.PI) da -= 2 * Math.PI; else if (da < -Math.PI) da += 2 * Math.PI;
      s.angle += da * k;
      const dr = tr - s.radius;
      s.radius += dr * k;
      const head = { x: Math.sin(s.angle) * s.radius, y: -Math.cos(s.angle) * s.radius };
      const tail = s.trail[s.trail.length - 1];
      if (s.radius > R_IN * 0.7 && (!tail || Math.hypot(tail.x - head.x, tail.y - head.y) > 1.5)) {
        s.trail.push(head);
        if (s.trail.length > 16) s.trail.shift();
      } else if (s.trail.length) s.trail.shift();
      let settled = Math.abs(da) < 0.002 && Math.abs(dr) < 0.3 && s.trail.length === 0;
      s.fills = s.fills.map((f, i) => {
        const goal = i === h ? closeness(s, i) : closeness(s, i) * 0.3;
        const next = f + (goal - f) * (1 - Math.exp(-dt * (goal > f ? 6 : 9)));
        if (Math.abs(goal - next) > 0.003) settled = false;
        return next;
      });
      s.wave += dt * 5;
      state.current = s;
      setInk(s);
      if (!settled) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hover, n, still, travel === undefined]);
  // Driven by a clock (the promo recorder): the drop is `travel` of the way there, then the pool fills.
  if (travel !== undefined && hover !== null && hover >= 0 && hover < n) {
    const ease = (p: number) => 1 - Math.pow(1 - Math.max(0, Math.min(1, p)), 3);
    const a = spot(hover, n).a, from = R_IN * 0.7, radius = from + (R_MID - from) * ease(travel / 0.55);
    const trail = travel < 0.6 ? Array.from({ length: 10 }, (_, k) => {
      const r = from + (radius - from) * (k / 9) * Math.min(1, 1 - (travel - 0.4) * 2.5);
      return { x: Math.sin(a) * r, y: -Math.cos(a) * r };
    }) : [];
    return { angle: a, radius, color: colors[hover], trail, fills: colors.map((_, i) => (i === hover ? ease((travel - 0.4) / 0.6) : 0)), wave: travel * 4 };
  }
  // Stills (the feature cards) never animate.
  return still ? settledInk() : ink;
}

export function Wheel({ x, y, mode, ops, hover, fileName, scale = 1, embedded = false, resize = false, travel }: {
  x: number; y: number; mode: Mode; ops: Op[]; hover: number | null; fileName: string; scale?: number; embedded?: boolean;
  /** 0→1 progress of the ink toward the hovered choice, for clock-driven recordings; omit to animate live. */
  travel?: number;
  /** Scale by resizing the SVG instead of a CSS transform. Slower, but text is redrawn crisply every frame,
   *  which the promo recorder needs (Chrome can leave SVG text stale under a changing CSS scale). */
  resize?: boolean;
}) {
  const n = Math.max(ops.length, 1);
  const colors = ops.map((op) => COLORS[op.category]);
  const ink = useInk(hover, colors, embedded, travel);
  const hovered = hover !== null && hover >= 0 ? ops[hover] : null;
  const size = (R_OUT + RIM + 8) * 2;
  const px = resize ? size * scale : size;
  const uid = useId().replace(/:/g, "");
  const caption = hover === -1 ? "Let go in the middle to cancel"
    : hovered?.ext ? `Convert ${fileName} to ${hovered.label}`
    : hovered ? `${hovered.label} · ${fileName}` : "Move toward a choice and let go";
  const centre = hover === -1 ? { text: "Cancel", color: "#d1331f" }
    : hovered ? { text: hovered.label, color: COLORS[hovered.category] }
    : { text: fileName.replace(/\.[^.]+$/, ""), color: "var(--sumi-ink-soft)" };
  const head = { x: Math.sin(ink.angle) * ink.radius, y: -Math.cos(ink.angle) * ink.radius };
  let dropAlpha = Math.max(0, Math.min(1, (ink.radius - R_IN * 0.75) / 14));
  if (hover !== null && hover >= 0 && hover < ops.length) {
    const p = spot(hover, n);
    dropAlpha *= Math.max(0, Math.min(1, Math.hypot(head.x - p.x, head.y - p.y) / (POOL * 0.9)));
  }
  const trail = [...ink.trail, head];
  const ring = R_IN - 8;

  return (
    <div className={embedded ? "wheel is-embedded" : "wheel"}
         style={embedded ? { width: size, height: size }
           : { left: x, top: y, width: px, height: px, "--scale": resize ? 1 : scale } as React.CSSProperties}>
      <svg viewBox={`${-size / 2} ${-size / 2} ${size} ${size}`} width={px} height={px} className="sumi">
        <defs>
          <radialGradient id={`vignette-${uid}`} r="50%">
            <stop offset="55%" stopColor="var(--sumi-ink)" stopOpacity="0" /><stop offset="100%" stopColor="var(--sumi-ink)" stopOpacity="0.07" />
          </radialGradient>
          <radialGradient id={`wash-${uid}`} cx="40%" cy="40%" r="65%">
            <stop offset="0%" stopColor="var(--sumi-ink)" stopOpacity="var(--sumi-wash)" /><stop offset="100%" stopColor="var(--sumi-ink)" stopOpacity="0.02" />
          </radialGradient>
        </defs>
        <circle r={R_OUT + RIM} className="sumi-paper" />
        <circle r={R_OUT + RIM} fill={`url(#vignette-${uid})`} />
        {ops.map((op, i) => {
          const p = spot(i, n), seed = i * 2.1 + 0.7, amount = ink.fills[i] ?? 0, color = colors[i];
          const level = p.y + POOL * 1.3 - POOL * 2.6 * amount;
          let surface = `M${p.x - POOL * 1.6},${p.y + POOL * 1.4}`;
          for (let xx = p.x - POOL * 1.6; xx <= p.x + POOL * 1.6; xx += 3) {
            surface += `L${xx.toFixed(1)},${(level - Math.sin(xx * 0.13 + ink.wave + i) * 2.4 * (1.2 - amount)).toFixed(1)}`;
          }
          surface += `L${p.x + POOL * 1.6},${p.y + POOL * 1.4}Z`;
          return (
            <g key={op.label + i}>
              <path d={poolPath(p.x, p.y, POOL, seed)} fill={`url(#wash-${uid})`} />
              {amount > 0.01 && (
                <>
                  <clipPath id={`pool-${uid}-${i}`}><path d={poolPath(p.x, p.y, POOL * 1.05, seed)} /></clipPath>
                  <path d={surface} fill={color} opacity={0.95} clipPath={`url(#pool-${uid}-${i})`}
                        style={amount > 0.5 ? { filter: `drop-shadow(0 0 ${10 * amount}px ${color})` } : undefined} />
                </>
              )}
            </g>
          );
        })}
        {dropAlpha > 0.01 && (
          <g style={{ filter: `drop-shadow(0 0 6px ${ink.color})` }} opacity={dropAlpha}>
            {trail.slice(1).map((pt, k) => (
              <line key={k} x1={trail[k].x} y1={trail[k].y} x2={pt.x} y2={pt.y} stroke={ink.color} strokeLinecap="round"
                    strokeWidth={2 + 9 * ((k + 1) / trail.length)} strokeOpacity={0.15 + 0.7 * ((k + 1) / trail.length)} />
            ))}
            <path d={poolPath(head.x, head.y, 7.5, ink.wave * 0.6)} fill={ink.color} />
            <ellipse cx={head.x - 2} cy={head.y - 2.2} rx={1.5} ry={1.2} fill="#fff" opacity={0.6} />
          </g>
        )}
        {ops.map((op, i) => {
          const p = spot(i, n), lit = (ink.fills[i] ?? 0) > 0.55, color = colors[i];
          const Icon = CATEGORY_ICONS[op.category];
          const hint = op.ext ? HINTS[op.ext] : undefined;
          const nameSize = Math.min(op.ext ? 12.5 : 10.5, (POOL * 1.85) / (op.label.length * 0.66));
          return (
            <g key={"l" + op.label + i}>
              <Icon x={p.x - 6} y={p.y - (hint ? 23 : 17)} width={12} height={12} color={lit ? "#fff" : color} strokeWidth={2.2} />
              <text x={p.x} y={p.y + (hint ? 1 : 4)} textAnchor="middle" dominantBaseline="central" className="sumi-name"
                    style={{ fontSize: nameSize }} fill={lit ? "#fff" : "var(--sumi-ink)"}>{op.label}</text>
              {hint && (
                <text x={p.x} y={p.y + 14} textAnchor="middle" dominantBaseline="central" className="sumi-hint"
                      fill={lit ? "#fff" : "var(--sumi-ink)"} opacity={0.7}>{hint}</text>
              )}
            </g>
          );
        })}
        {Array.from({ length: 160 }, (_, k) => {
          const t = k / 160, a = Math.PI * 0.62 + Math.PI * 1.85 * t;
          const w = (1 - t * 0.6) * 4 + wobble(t * 9, 1) * 0.6, rr = ring + wobble(t * 4, 3) * 1.2;
          return <circle key={k} cx={r2(Math.cos(a) * rr)} cy={r2(-Math.sin(a) * rr)} r={r2(w / 2)} className="sumi-ring" />;
        })}
        <File x={-10} y={-26} width={20} height={20} color="var(--sumi-ink-soft)" strokeWidth={1.6} opacity={hover === -1 ? 0.35 : 1} />
        <text y={7} textAnchor="middle" dominantBaseline="central" className="sumi-centre"
              style={{ fontSize: hovered || hover === -1 ? 11.5 : 9.5 }} fill={centre.color}>{centre.text}</text>
        {(Object.keys(MODE_KEYS) as Mode[]).map((m, i) => {
          const Icon = MODE_ICONS[m], on = m === mode;
          return <Icon key={m} x={(i - 1) * 18 - (on ? 5 : 4.5)} y={22} width={on ? 10 : 9} height={on ? 10 : 9}
                       color={on ? MODE_COLORS[m] : "var(--sumi-ink)"} opacity={on ? 1 : 0.25} strokeWidth={2.4} />;
        })}
      </svg>
      {!embedded && <div className="wheel-caption">{caption}</div>}
    </div>
  );
}

/** A static, scaled-down wheel for feature cards. */
export function MiniWheel({ mode, hover }: { mode: Mode; hover: number }) {
  const size = (R_OUT + RIM + 8) * 2;
  return (
    <div className="mini-wheel" style={{ "--mini": 0.62, width: size * 0.62, height: size * 0.62 } as React.CSSProperties}>
      <Wheel x={0} y={0} mode={mode} ops={OPS.photo[mode]} hover={hover} fileName="Vacation.heic" embedded />
    </div>
  );
}

export function FileIcon({ kind, name }: { kind: DemoFile["kind"]; name: string }) {
  const ext = name.split(".").pop()!.toUpperCase();
  if (kind === "photo") {
    return (
      <span className="file-icon file-photo">
        <span className="file-photo-sun" /><span className="file-photo-hill" />
        <span className="file-ext">{ext}</span>
      </span>
    );
  }
  if (kind === "video") {
    return <span className="file-icon file-video"><span className="file-play">▶</span><span className="file-ext">{ext}</span></span>;
  }
  return (
    <span className="file-icon file-doc">
      <span className="file-lines" /><span className="file-ext">{ext}</span>
    </span>
  );
}
