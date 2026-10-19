import type { Metadata } from "next";
import { MiniWheel } from "../components/WheelDemo";
import "./banner.css";

// 1280×640 README banner, captured in light and dark (docs/images/banner-*.png). Not linked anywhere.
export const metadata: Metadata = { title: "Kaeru — banner", robots: { index: false } };

export default function Banner() {
  return (
    <div className="banner">
      <div className="banner-copy">
        <div className="banner-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/shots/icon.png" alt="" width={84} height={84} />
          <div>
            <h1>Kaeru</h1>
            <span className="maru">かえる · to change</span>
          </div>
        </div>
        <p className="banner-pitch">Change any file<br /><span className="grad">without opening an app.</span></p>
        <p className="banner-how">Drag a file · hold <kbd>⇧</kbd> · drop on a format</p>
        <div className="banner-chips">
          <span>350+ conversions</span><span>On-device</span><span>Free &amp; open source</span>
        </div>
      </div>
      <div className="banner-wheel">
        <MiniWheel mode="convert" hover={0} />
      </div>
    </div>
  );
}
