import type { Metadata, Viewport } from "next";
import { Geist, Shippori_Mincho, Zen_Maru_Gothic } from "next/font/google";
import "./globals.css";

const sans = Geist({ variable: "--font-sans", subsets: ["latin"] });
// Rounded Japanese face for the かえる wordmark accents.
const maru = Zen_Maru_Gothic({ variable: "--font-maru", weight: ["700"], subsets: ["latin"] });
// Japanese serif for the sumi-e picker's labels where Hiragino Mincho isn't installed.
const mincho = Shippori_Mincho({ variable: "--font-mincho", weight: ["400", "600"], subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://getkaeru.vercel.app"),
  title: "Kaeru: change any file without opening an app",
  description:
    "Drag a file, hold a key, drop it on what you want. 350+ conversions, trim, crop, OCR and background removal. Free, open source and 100% on your Mac.",
  openGraph: {
    title: "Kaeru: change any file without opening an app",
    description: "Drag, hold ⇧, drop. 350+ private, on-device conversions for macOS. Free and open source.",
    type: "website",
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f7fbf8" },
    { media: "(prefers-color-scheme: dark)", color: "#0a0f0c" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${sans.variable} ${maru.variable} ${mincho.variable}`}>
      <body>{children}</body>
    </html>
  );
}
