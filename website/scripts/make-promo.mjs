// Records the promo (app/promo) frame by frame at 1920×1080, 30 fps.
//
// It is a Playwright script: it receives an open page on /promo?drive=1 and steps the promo's clock
// through every frame, saving each one once it has painted. Then build the video with ffmpeg:
//
//   npx next dev -p 3123
//   FRAMES=/tmp/promo-frames node <browser-automation skill>/browser.mjs \
//     "http://localhost:3123/promo?drive=1" --script scripts/make-promo.mjs --timeout 600000
//   python3 scripts/promo_audio.py /tmp/promo.wav
//   ffmpeg -framerate 30 -i /tmp/promo-frames/f%04d.png -i /tmp/promo.wav \
//     -c:v libx264 -pix_fmt yuv420p -crf 18 -c:a aac -b:a 192k -shortest public/kaeru-promo.mp4
import { mkdirSync } from "node:fs";

const FPS = 30, DURATION = 25;

export default async function record(page) {
  const out = process.env.FRAMES ?? "/tmp/promo-frames";
  mkdirSync(out, { recursive: true });
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.waitForFunction(() => document.documentElement.dataset.promoReady === "1", null, { timeout: 60000 });
  await page.addStyleTag({ content: "nextjs-portal { display: none !important; }" });
  const promo = page.locator(".promo");
  const frames = FPS * DURATION;
  for (let k = 0; k < frames; k++) {
    const t = k / FPS;
    await page.evaluate((v) => {
      const root = document.documentElement;
      delete root.dataset.promoFrame;
      root.dataset.promoT = String(v);
      document.dispatchEvent(new Event("promo-time"));
    }, t);
    await page.waitForFunction((v) => document.documentElement.dataset.promoFrame === String(v), t, { timeout: 10000 });
    await promo.screenshot({ path: `${out}/f${String(k).padStart(4, "0")}.png` });
  }
  return { frames, out };
}
