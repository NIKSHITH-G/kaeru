import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const alt = "Kaeru — change any file without opening an app";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  const icon = await readFile(join(process.cwd(), "public/shots/icon.png"));
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%", height: "100%", display: "flex", alignItems: "center", gap: 56, padding: "0 90px",
          background: "radial-gradient(900px 500px at 15% 10%, #bff0d6, transparent), linear-gradient(135deg, #f2fbf6, #dff3fb)",
          fontFamily: "sans-serif",
        }}
      >
        <img src={iconSrc} width={300} height={300} alt="" />
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ fontSize: 88, fontWeight: 800, color: "#0d1f17", letterSpacing: -3 }}>Kaeru</div>
          <div style={{ fontSize: 40, color: "#0d1f17", lineHeight: 1.2, maxWidth: 640 }}>
            Change any file without opening an app.
          </div>
          <div style={{ fontSize: 26, color: "#058561" }}>Drag · hold ⇧ · drop — 350+ conversions, all on your Mac</div>
        </div>
      </div>
    ),
    size,
  );
}
