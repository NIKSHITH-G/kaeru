"use client";

import { Play, X } from "lucide-react";
import { useEffect, useState } from "react";
import { COLORS, type Category } from "../site";

/** "Turn HEIC into JPG." — the format pair flips every couple of seconds. */
const PAIRS: [string, Category, string, Category][] = [
  ["HEIC", "image", "JPG", "image"],
  ["MOV", "video", "MP4", "video"],
  ["DOCX", "document", "PDF", "pdf"],
  ["PDF", "pdf", "PPTX", "slides"],
  ["WAV", "audio", "MP3", "audio"],
  ["CSV", "spreadsheet", "XLSX", "spreadsheet"],
  ["PNG", "image", "WebP", "image"],
];

export function FormatFlipper() {
  const [i, setI] = useState(0);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const id = setInterval(() => setI((n) => (n + 1) % PAIRS.length), 2200);
    return () => clearInterval(id);
  }, []);
  const [from, fromCat, to, toCat] = PAIRS[i];
  return (
    <span className="flipper" aria-hidden>
      Turn{" "}
      <span key={`a${i}`} className="flip-badge" style={{ background: COLORS[fromCat] }}>{from}</span>{" "}
      into{" "}
      <span key={`b${i}`} className="flip-badge flip-late" style={{ background: COLORS[toCat] }}>{to}</span>.
    </span>
  );
}

/** "Watch the video" button with an in-page player. */
export function VideoButton() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const close = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [open]);
  return (
    <>
      <button className="btn btn-ghost" onClick={() => setOpen(true)}>
        <Play size={15} fill="currentColor" /> Watch the video
      </button>
      {open && (
        <div className="video-modal" onClick={() => setOpen(false)} role="dialog" aria-label="Kaeru in 25 seconds">
          <div className="video-frame" onClick={(e) => e.stopPropagation()}>
            <video src="/kaeru-promo.mp4" autoPlay controls playsInline />
            <button className="video-close" onClick={() => setOpen(false)} aria-label="Close video"><X size={18} /></button>
          </div>
        </div>
      )}
    </>
  );
}

/** Format chips drifting slowly behind the hero, for depth. Purely decorative. */
export function DriftingChips() {
  const chips: [string, Category, number, number, number][] = [
    ["HEIC", "image", 6, 18, 0], ["MP4", "video", 88, 14, 1.5], ["PDF", "pdf", 12, 62, 3], ["MP3", "audio", 84, 58, 0.8],
    ["DOCX", "document", 4, 40, 2.2], ["XLSX", "spreadsheet", 93, 36, 3.6], ["GIF", "image", 20, 84, 1.1], ["EPUB", "document", 78, 82, 2.7],
  ];
  return (
    <div className="drift" aria-hidden>
      {chips.map(([label, cat, x, y, delay]) => (
        <span key={label} className="drift-chip"
              style={{ left: `${x}%`, top: `${y}%`, background: COLORS[cat], animationDelay: `-${delay * 2}s` }}>
          {label}
        </span>
      ))}
    </div>
  );
}
