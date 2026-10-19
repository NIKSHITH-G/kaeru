import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    { url: "https://getkaeru.vercel.app", changeFrequency: "weekly", priority: 1 },
    { url: "https://getkaeru.vercel.app/install", changeFrequency: "monthly", priority: 0.8 },
  ];
}
