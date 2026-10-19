export const REPO = "NIKSHITH-G/kaeru";
export const GITHUB_URL = `https://github.com/${REPO}`;
export const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Kaeru.dmg`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;

/** Category colours, matching Theme.swift in the app. */
export const COLORS = {
  image: "#A855F7",
  video: "#F43F5E",
  audio: "#F59E0B",
  document: "#3B82F6",
  pdf: "#EF4444",
  spreadsheet: "#10B981",
  slides: "#F97316",
  data: "#64748B",
  archive: "#CA8A04",
  tool: "#6366F1",
  action: "#06B6D4",
  brand: "#22C578",
} as const;

export type Category = keyof typeof COLORS;

export const FORMAT_GROUPS: { name: string; category: Category; inputs: string[]; outputs: string[] }[] = [
  { name: "Images", category: "image", inputs: ["HEIC", "JPG", "PNG", "WebP", "AVIF", "TIFF", "GIF", "BMP", "SVG", "PSD", "RAW"],
    outputs: ["JPG", "PNG", "HEIC", "WebP", "AVIF", "TIFF", "GIF", "BMP", "PDF", "ICO", "ICNS"] },
  { name: "Video", category: "video", inputs: ["MP4", "MOV", "MKV", "WebM", "AVI", "WMV", "M4V"],
    outputs: ["MP4", "MOV", "MKV", "WebM", "AVI", "WMV", "GIF", "MP3", "M4A", "WAV"] },
  { name: "Audio", category: "audio", inputs: ["MP3", "M4A", "WAV", "FLAC", "OGG", "Opus", "AIFF", "WMA"],
    outputs: ["MP3", "M4A", "WAV", "FLAC", "OGG", "Opus", "AIFF", "WMA"] },
  { name: "PDF", category: "pdf", inputs: ["PDF"],
    outputs: ["PNG", "JPG", "PPTX", "EPUB", "DOCX", "Markdown", "TXT", "RTF", "HTML"] },
  { name: "Documents", category: "document", inputs: ["DOCX", "DOC", "ODT", "RTF", "Markdown", "HTML", "TXT", "EPUB", "Pages"],
    outputs: ["DOCX", "PDF", "EPUB", "Markdown", "HTML", "RTF", "ODT", "TXT"] },
  { name: "Slides", category: "slides", inputs: ["PPTX", "PPT", "Keynote"], outputs: ["PDF", "PNG", "JPG"] },
  { name: "Spreadsheets", category: "spreadsheet", inputs: ["XLSX", "XLS", "ODS", "CSV", "TSV"],
    outputs: ["XLSX", "ODS", "CSV", "TSV", "JSON", "HTML", "Markdown", "PDF"] },
  { name: "Data & subtitles", category: "data", inputs: ["JSON", "PLIST", "SRT", "VTT"],
    outputs: ["CSV", "XLSX", "PLIST", "JSON", "SRT", "VTT", "TXT"] },
  { name: "Archives", category: "archive", inputs: ["ZIP", "RAR", "7Z", "TAR", "GZ"], outputs: ["Extract", "ZIP", "TAR.GZ"] },
];

/** Latest release info, refreshed hourly; falls back gracefully if GitHub is unreachable. */
export async function latestRelease(): Promise<{ version: string; sizeMB: number | null }> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
      next: { revalidate: 3600 },
    });
    if (!res.ok) throw new Error(String(res.status));
    const json = await res.json();
    const dmg = (json.assets ?? []).find((a: { name: string }) => a.name.endsWith(".dmg"));
    return { version: String(json.tag_name ?? "").replace(/^v/, ""), sizeMB: dmg ? Math.round(dmg.size / 1e6) : null };
  } catch {
    return { version: "", sizeMB: null };
  }
}

export type ReleaseNote = { version: string; date: string; title: string; points: string[]; url: string };

/** The latest few releases for "What's new", parsed from each release's Markdown notes. */
export async function recentReleases(count = 3): Promise<ReleaseNote[]> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=${count}`, {
      headers: { Accept: "application/vnd.github+json" },
      next: { revalidate: 3600 },
    });
    if (!res.ok) return [];
    const releases: { tag_name: string; published_at: string; body: string | null; html_url: string; name: string }[] = await res.json();
    return releases.map((r) => {
      const lines = (r.body ?? "").split("\n").map((l) => l.trim());
      const heading = lines.find((l) => l.startsWith("### "))?.slice(4);
      const points = lines.filter((l) => l.startsWith("- ")).slice(0, 4)
        .map((l) => l.slice(2).replace(/\*\*(.+?)\*\*/g, "$1").replace(/`(.+?)`/g, "$1"));
      return {
        version: r.tag_name.replace(/^v/, ""),
        date: new Date(r.published_at).toLocaleDateString("en", { month: "short", day: "numeric", year: "numeric" }),
        title: heading ?? (points.length ? "Highlights" : r.name),
        points,
        url: r.html_url,
      };
    });
  } catch {
    return [];
  }
}
