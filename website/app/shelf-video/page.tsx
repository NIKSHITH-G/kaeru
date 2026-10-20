import type { Metadata } from "next";
import ShelfVideo from "./ShelfVideo";

// The source of the shelf video (scripts/make-promo.mjs records it frame by frame, with DURATION=22).
export const metadata: Metadata = { title: "Kaeru shelf video", robots: { index: false } };

export default function ShelfVideoPage() {
  return <ShelfVideo />;
}
