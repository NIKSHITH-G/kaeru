import type { Metadata } from "next";
import Promo from "./Promo";

// The source of the shareable promo video (scripts/make-promo.mjs records it frame by frame).
export const metadata: Metadata = { title: "Kaeru — promo", robots: { index: false } };

export default function PromoPage() {
  return <Promo />;
}
