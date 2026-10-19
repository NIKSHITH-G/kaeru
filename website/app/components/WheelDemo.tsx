"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { COLORS, type Category } from "../site";

type Mode = "convert" | "tools" | "actions";
type Op = { label: string; hint?: string; ext?: string; category: Category; result: (name: string) => string };

type DemoFile = { id: string; name: string; kind: "photo" | "video" | "doc"; x: number; y: number; fresh?: boolean };

const base = (n: string) => n.replace(/\.[^.]+$/, "");
const convert = (ext: string, category: Category, hint?: string): Op => ({
  label: ext.toUpperCase(), ext: ext.toLowerCase(), hint, category, result: (n) => `${base(n)}.${ext.toLowerCase()}`,
});
const tool = (label: string, result: (n: string) => string): Op => ({ label, category: "tool", result });
const action = (label: string, message: string): Op => ({ label, category: "action", result: () => message });

const ACTIONS: Op[] = [
  action("AirDrop", "Sent with AirDrop"), action("Float", "Floating above your windows"), action("Copy", "Copied — paste in Finder"),
  action("Copy Path", "Copied path"), action("Move To…", "Moved to Documents"), action("Terminal", "Opened Terminal here"),
  action("Reveal", "Shown in Finder"),
];

const OPS: Record<DemoFile["kind"], Record<Mode, Op[]>> = {
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
const MODE_TITLES: Record<Mode, string> = { convert: "Convert", tools: "Tools", actions: "Actions" };
const MODE_COLORS: Record<Mode, string> = { convert: COLORS.brand, tools: COLORS.tool, actions: COLORS.action };

const INITIAL: DemoFile[] = [
  { id: "a", name: "Vacation.heic", kind: "photo", x: 0.18, y: 0.3 },
  { id: "b", name: "Interview.mov", kind: "video", x: 0.18, y: 0.72 },
  { id: "c", name: "Thesis.docx", kind: "doc", x: 0.82, y: 0.3 },
];

// Same proportions as the app's wheel: rounded tiles on a pale plate.
const R_IN = 62, R_OUT = 152, R_MID = (R_IN + R_OUT) / 2, RIM = 9, GAP = 7, CORNER = 15;

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
  const still = useRef<{ timer: ReturnType<typeof setTimeout> | null; x: number; y: number }>({ timer: null, x: 0, y: 0 });

  const ops = drag && wheel ? OPS[drag.file.kind][wheel.mode] : [];

  const local = useCallback((clientX: number, clientY: number) => {
    const r = stage.current!.getBoundingClientRect();
    return { x: clientX - r.left, y: clientY - r.top };
  }, []);

  const sliceAt = useCallback((x: number, y: number, w: { x: number; y: number }, count: number) => {
    const dx = x - w.x, dy = y - w.y, r = Math.hypot(dx, dy);
    if (r < R_IN) return -1;
    if (r > R_OUT + 20 || count === 0) return null;
    let theta = Math.atan2(dx, -dy);           // clockwise from 12 o'clock
    if (theta < 0) theta += 2 * Math.PI;
    return Math.min(Math.floor(theta / ((2 * Math.PI) / count)), count - 1);
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
      if (mode && drag) { e.preventDefault(); openWheel(mode); }
      if (e.key === "Escape") { setWheel(null); setDrag(null); }
    };
    window.addEventListener("keydown", down);
    return () => window.removeEventListener("keydown", down);
  }, [drag, openWheel]);

  const onPointerDown = (file: DemoFile) => (e: React.PointerEvent) => {
    e.preventDefault();
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
    if (!drag) return;
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
    if (still.current.timer) clearTimeout(still.current.timer);
    if (drag && wheel && hover !== null && hover >= 0 && ops[hover]) {
      const op = ops[hover];
      const text = op.result(drag.file.name);
      setToast({ text, ok: true });
      setTried(true);
      if (op.category !== "action" && !text.includes("words")) {
        const name = text.split(" · ")[0];
        const kind: DemoFile["kind"] = /\.(mp4|mov|mkv|webm|gif)$/.test(name) && !name.endsWith(".gif") ? "video"
          : /\.(jpg|png|webp|avif|tiff|gif|ico|heic)$/.test(name) ? "photo" : "doc";
        setFiles((fs) => [...fs.slice(-5), {
          id: Math.random().toString(36).slice(2), name, kind, fresh: true,
          x: Math.min(0.82, Math.max(0.18, drag.file.x + 0.2 * (drag.file.x > 0.5 ? -1 : 1))),
          y: Math.min(0.78, drag.file.y + 0.12 * fs.filter((f) => f.fresh).length + 0.02),
        }]);
      }
    }
    setDrag(null);
    setWheel(null);
    setHover(null);
  };

  return (
    <div className="demo">
      <div
        ref={stage}
        className="demo-stage"
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
          <Wheel x={wheel.x} y={wheel.y} mode={wheel.mode} ops={ops} hover={hover} fileName={drag.file.name} />
        )}

        {!drag && !tried && (
          <div className="demo-hint">
            <b>Try it:</b> drag a file, then press <kbd>⇧</kbd> <kbd>⌘</kbd> or <kbd>⌃</kbd>
            <span className="demo-hint-touch"> — on touch, pause while dragging</span>
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
        This is a live demo of Kaeru&rsquo;s wheel. On your Mac it works on real files, anywhere.
      </p>
    </div>
  );
}

const HINTS: Record<string, string> = {
  jpg: "works everywhere", png: "lossless", webp: "small, for the web", avif: "smallest", pdf: "document",
  mp4: "plays everywhere", gif: "animated", mp3: "plays everywhere", wav: "lossless", md: "plain text", epub: "e-book",
};

/** A rounded annular tile with parallel gaps, matching tilePath() in WheelView.swift. */
function tilePath(i: number, n: number, ro: number) {
  const step = (2 * Math.PI) / n, h = GAP / 2, ri = R_IN;
  const pt = (r: number, a: number) => [Math.sin(a) * r, -Math.cos(a) * r];
  if (n === 1) return `M0,${-ro} A${ro},${ro} 0 1 1 0,${ro} A${ro},${ro} 0 1 1 0,${-ro} Z M0,${-ri} A${ri},${ri} 0 1 0 0,${ri} A${ri},${ri} 0 1 0 0,${-ri} Z`;
  const a0 = i * step, a1 = (i + 1) * step;
  const os = a0 + Math.asin(h / ro), oe = a1 - Math.asin(h / ro), is = a0 + Math.asin(h / ri), ie = a1 - Math.asin(h / ri);
  const co = CORNER / ro, ci = (CORNER * 0.75) / ri;
  const [osx, osy] = pt(ro, os), [oex, oey] = pt(ro, oe), [isx, isy] = pt(ri, is), [iex, iey] = pt(ri, ie);
  const along = (x0: number, y0: number, x1: number, y1: number, d: number) => {
    const len = Math.hypot(x1 - x0, y1 - y0);
    return [x0 + ((x1 - x0) / len) * d, y0 + ((y1 - y0) / len) * d];
  };
  const [s0x, s0y] = along(osx, osy, isx, isy, CORNER), [s1x, s1y] = pt(ro, os + co), [s2x, s2y] = pt(ro, oe - co);
  const [s3x, s3y] = along(oex, oey, iex, iey, CORNER), [s4x, s4y] = along(iex, iey, oex, oey, CORNER * 0.75);
  const [s5x, s5y] = pt(ri, ie - ci), [s6x, s6y] = pt(ri, is + ci), [s7x, s7y] = along(isx, isy, osx, osy, CORNER * 0.75);
  const large = oe - os > Math.PI ? 1 : 0;
  return `M${s0x},${s0y} Q${osx},${osy} ${s1x},${s1y} A${ro},${ro} 0 ${large} 1 ${s2x},${s2y} Q${oex},${oey} ${s3x},${s3y}
    L${s4x},${s4y} Q${iex},${iey} ${s5x},${s5y} A${ri},${ri} 0 ${large} 0 ${s6x},${s6y} Q${isx},${isy} ${s7x},${s7y} Z`;
}

function Wheel({ x, y, mode, ops, hover, fileName }: {
  x: number; y: number; mode: Mode; ops: Op[]; hover: number | null; fileName: string;
}) {
  const n = Math.max(ops.length, 1);
  const step = (2 * Math.PI) / n;
  const hovered = hover !== null && hover >= 0 ? ops[hover] : null;
  const accent = MODE_COLORS[mode];
  const size = (R_OUT + RIM + 8) * 2;
  const pill = hover === -1 ? "Cancel" : hovered ? hovered.label : MODE_TITLES[mode];
  const pillWidth = Math.max(96, pill.length * 9 + 40);
  const caption = hover === -1 ? "Drop here to cancel"
    : hovered?.ext ? `Convert ${fileName} to ${hovered.label}${HINTS[hovered.ext] ? ` · ${HINTS[hovered.ext]}` : ""}`
    : hovered ? `${hovered.label} · ${fileName}` : fileName;

  return (
    <div className="wheel" style={{ left: x, top: y, width: size, height: size }}>
      <svg viewBox={`${-size / 2} ${-size / 2} ${size} ${size}`} width={size} height={size}>
        <defs>
          <radialGradient id="tile-light" cx="50%" cy="50%" r="60%">
            <stop offset="0%" stopColor="var(--tile-hi)" /><stop offset="100%" stopColor="var(--tile-lo)" />
          </radialGradient>
          <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--plate-hi)" /><stop offset="100%" stopColor="var(--plate-lo)" />
          </linearGradient>
        </defs>
        <circle r={R_OUT + RIM} fill="url(#plate)" className="wheel-plate" />
        {ops.map((op, i) => {
          const on = i === hover;
          const a = (i + 0.5) * step;
          const lx = Math.sin(a) * R_MID, ly = -Math.cos(a) * R_MID;
          return (
            <g key={op.label + i} className={on ? "tile is-on" : "tile"}>
              <path d={tilePath(i, n, on ? R_OUT + 5 : R_OUT)} fill={on ? accent : "url(#tile-light)"}
                    style={on ? { filter: `drop-shadow(0 6px 14px ${accent}73)` } : undefined} />
              <text x={lx} y={ly} textAnchor="middle" dominantBaseline="central"
                    className={op.ext ? "tile-format" : "tile-label"} fill={on ? "#fff" : "var(--fg)"}>{op.label}</text>
            </g>
          );
        })}
        <rect x={-pillWidth / 2} y={-27} width={pillWidth} height={40} rx={20} className="wheel-pill" />
        <text y={-7} textAnchor="middle" dominantBaseline="central" className="wheel-pill-text"
              fill={hover === -1 ? "#ef4444" : hovered ? "var(--fg)" : "var(--muted)"}>{pill}</text>
        {(Object.keys(MODE_KEYS) as Mode[]).map((m, i) => (
          <g key={m} transform={`translate(${(i - 1) * 24},${26})`}>
            <rect x={-10} y={-8} width={20} height={16} rx={5} fill={m === mode ? `${accent}29` : "transparent"} />
            <text textAnchor="middle" dy="4" className="wheel-key" fill={m === mode ? accent : "var(--muted)"}>{MODE_KEYS[m]}</text>
          </g>
        ))}
      </svg>
      <div className="wheel-caption">{caption}</div>
    </div>
  );
}

function FileIcon({ kind, name }: { kind: DemoFile["kind"]; name: string }) {
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
