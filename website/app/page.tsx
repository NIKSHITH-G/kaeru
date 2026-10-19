import Image from "next/image";
import { CornerDownLeft, Download, Gauge, Keyboard, MousePointerClick, RefreshCw, Scissors, Sparkles } from "lucide-react";
import { CopyCommand, PlatformNote } from "./components/Bits";
import { DriftingChips, FormatFlipper, VideoButton } from "./components/Hero";
import WheelDemo, { MiniWheel } from "./components/WheelDemo";
import { COLORS, DOWNLOAD_URL, FORMAT_GROUPS, GITHUB_URL, RELEASES_URL, latestRelease, recentReleases } from "./site";

function GitHubMark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" aria-hidden fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

const WHEELS = [
  { key: "⇧", name: "Convert", color: COLORS.brand, mode: "convert" as const, hover: 0,
    body: "Every format your file can become, in one ring. HEIC → JPG, MOV → MP4, DOCX → PDF, PDF → PPTX.",
    chips: ["JPG", "MP4", "PDF", "WebP", "MP3", "XLSX", "EPUB"] },
  { key: "⌘", name: "Tools", color: COLORS.tool, mode: "tools" as const, hover: 1,
    body: "Edit without an editor: trim and crop, compress, merge clips, remove backgrounds, pull text out of images.",
    chips: ["Trim", "Crop", "Compress", "Remove BG", "OCR", "Merge"] },
  { key: "⌃", name: "Actions", color: COLORS.action, mode: "actions" as const, hover: 0,
    body: "Things you do with files: AirDrop them, float them above every window, copy the path, open Terminal there.",
    chips: ["AirDrop", "Float", "Copy Path", "Move To", "Terminal"] },
];

const FEATURES = [
  { icon: CornerDownLeft, title: "Return in Finder", body: "Select files and press Return — the wheel opens, no drag needed. Renaming still works." },
  { icon: Scissors, title: "Trim & crop built in", body: "A QuickTime-style trimmer and a crop tool with aspect presets, opened right from the wheel." },
  { icon: Sparkles, title: "On-device AI", body: "Remove backgrounds, recognise text and make scanned PDFs searchable — with Apple's Vision, offline." },
  { icon: Gauge, title: "See what's happening", body: "Live progress, one-click cancel, and a record of how much space compression saved." },
  { icon: RefreshCw, title: "Updates itself", body: "New versions install from inside the app. No App Store, no account." },
  { icon: Keyboard, title: "Your keys, your way", body: "Pick Shift, ⌘, ⌃, ⌥, fn or Tab for each wheel. Keyboard-only control with arrows and Return." },
];

const COMPARE: [string, string, string][] = [
  ["Your files stay on your Mac", "✓", "Uploaded to a server"],
  ["Works offline", "✓", "—"],
  ["File size limits", "None", "Often 50–100 MB"],
  ["Batch & merge", "✓", "Usually paid"],
  ["Ads, sign-up, watermarks", "None", "Common"],
  ["Price", "Free & open source", "Subscriptions"],
];

const FAQ = [
  { q: "Is Kaeru really free?", a: "Yes. It's open source under the MIT license, with no ads, accounts or tracking. The code is on GitHub." },
  { q: "Why does macOS say Kaeru can't be opened?", a: "Kaeru isn't signed with a paid Apple Developer certificate yet. Click Done, then open System Settings → Privacy & Security, scroll to Security and click Open Anyway. You only do this once — the step-by-step guide at getkaeru.vercel.app/install shows every click." },
  { q: "Does it upload my files?", a: "Never. Every conversion runs on your Mac using Apple's frameworks and a bundled FFmpeg. The only network request is an optional daily update check against GitHub." },
  { q: "Which Macs does it run on?", a: "Apple silicon Macs with macOS 13 Ventura or later. Background removal needs macOS 14." },
  { q: "I already use Shift for another drag tool.", a: "Change the key for any wheel in Settings — ⌥ Option, fn and Tab are all available." },
  { q: "What about PowerPoint and Pages files?", a: "Slides convert with PowerPoint or Keynote if installed, and with a built-in renderer otherwise. Pages documents use the Pages app." },
];

export default async function Home() {
  const [release, releases] = await Promise.all([latestRelease(), recentReleases(3)]);
  const totalConversions = 351;

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify({
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            name: "Kaeru",
            applicationCategory: "UtilitiesApplication",
            operatingSystem: "macOS 13 or later",
            offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
            downloadUrl: DOWNLOAD_URL,
            softwareVersion: release.version || undefined,
            description: "Drag a file, hold a key, drop it on what you want. 350+ private, on-device conversions for macOS.",
          }),
        }}
      />
      <header className="nav">
        <a href="#" className="brand"><Image src="/shots/icon.png" alt="" width={30} height={30} priority />Kaeru</a>
        <nav>
          <a href="#how">How it works</a>
          <a href="#formats">Formats</a>
          <a href="/install">Install</a>
          <a href="#faq">FAQ</a>
          <a href={GITHUB_URL} className="nav-gh" aria-label="GitHub"><GitHubMark size={18} /></a>
          <a href={DOWNLOAD_URL} className="btn btn-small">Download</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <DriftingChips />
          {releases[0] && (
            <a href={releases[0].url} className="news-pill">
              <span className="news-tag">New</span><span>v{releases[0].version} · {releases[0].title}</span><span aria-hidden>→</span>
            </a>
          )}
          <h1>
            <span className="sr-only">Kaeru: change any file without opening anything.</span>
            <FormatFlipper />
            <br /><span className="grad">Without opening anything.</span>
          </h1>
          <p className="lede">
            Drag a file, hold <kbd>⇧</kbd>, drop it on what you want. <span className="maru">かえる</span> (kaeru)
            means “to change” — and it turns every drag into a converter, editor and share menu, without uploading a byte.
          </p>
          <div className="cta">
            <a href={DOWNLOAD_URL} className="btn btn-big">
              <svg width="18" height="18" viewBox="0 0 16 16" aria-hidden><path fill="currentColor" d="M8 1v9.6l3.3-3.3 1.4 1.4L8 13.4 3.3 8.7l1.4-1.4L7 10.6V1h2zM2 14h12v2H2z" /></svg>
              <span>Download for macOS<small>{release.version ? `v${release.version}` : "Free"}{release.sizeMB ? ` · ${release.sizeMB} MB` : ""} · Apple silicon</small></span>
            </a>
            <VideoButton />
            <a href={GITHUB_URL} className="btn btn-ghost btn-icon" aria-label="View source on GitHub"><GitHubMark size={18} /></a>
          </div>
          <div className="trust">
            <span>Free &amp; open source</span><span>{totalConversions} conversions</span><span>Nothing uploaded</span><span>macOS 13+</span>
          </div>
          <PlatformNote />
          <WheelDemo />
        </section>

        <section className="stats">
          <div><b>{totalConversions}</b><span>conversions</span></div>
          <div><b>30+</b><span>tools</span></div>
          <div><b>7</b><span>actions</span></div>
          <div><b>0</b><span>uploads</span></div>
        </section>

        <section id="how" className="section">
          <h2>Three keys. Three wheels.</h2>
          <p className="section-lede">Start dragging a file from anywhere, press a key, and the wheel appears under your cursor. Switch keys mid-drag to switch wheels.</p>
          <div className="wheels">
            {WHEELS.map((w) => (
              <article key={w.name} className="card wheel-card" style={{ "--accent": w.color } as React.CSSProperties}>
                <MiniWheel mode={w.mode} hover={w.hover} />
                <div className="wheel-card-head"><kbd className="kbd-lg">{w.key}</kbd><h3>{w.name}</h3></div>
                <p>{w.body}</p>
                <div className="chips">{w.chips.map((c) => <span key={c} className="chip">{c}</span>)}</div>
              </article>
            ))}
          </div>
        </section>

        <section className="section">
          <h2>Thought through, down to the details</h2>
          <div className="features">
            {FEATURES.map((f) => (
              <div key={f.title} className="feature">
                <span className="feature-icon"><f.icon size={19} strokeWidth={2.2} /></span>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="section shots">
          <div className="shot shot-main">
            <Image src="/shots/home.png" alt="Kaeru's main window" width={1720} height={1240} sizes="(max-width: 900px) 100vw, 60vw" />
          </div>
          <div className="shot-side">
            <div className="shot">
              <Image src="/shots/tutorial.png" alt="The hands-on tutorial" width={1120} height={1056} sizes="(max-width: 900px) 100vw, 35vw" />
            </div>
            <p className="shot-caption"><b>Learn it in 30 seconds.</b> The first-run tutorial hands you a sample file to try the wheel on — and celebrates when you do.</p>
          </div>
        </section>

        <section id="install" className="section">
          <h2>Installed in under a minute</h2>
          <p className="section-lede">No App Store, no account. Kaeru isn’t signed with a paid Apple certificate yet, so macOS asks you to approve it once.</p>
          <ol className="steps">
            <li className="card step">
              <span className="step-n">1</span>
              <div className="step-art step-art-download"><Download size={30} strokeWidth={2} /></div>
              <h3>Download</h3>
              <p>Get <b>Kaeru.dmg</b>{release.sizeMB ? ` (${release.sizeMB} MB)` : ""}. FFmpeg is built in, so there&rsquo;s nothing else to install.</p>
              <a href={DOWNLOAD_URL} className="btn btn-small">Download</a>
            </li>
            <li className="card step">
              <span className="step-n">2</span>
              <div className="step-art step-art-drag">
                <Image src="/shots/icon.png" alt="" width={46} height={46} />
                <span className="step-arrow">→</span>
                <span className="step-folder">Applications</span>
              </div>
              <h3>Drag to Applications</h3>
              <p>Open the DMG and drag the frog onto the Applications folder.</p>
            </li>
            <li className="card step">
              <span className="step-n">3</span>
              <div className="step-art step-art-menu">
                <span className="menu-item is-dim">Privacy &amp; Security</span>
                <span className="menu-item is-dim">“Kaeru” was blocked to protect your Mac.</span>
                <span className="menu-item">Open Anyway</span>
                <MousePointerClick size={20} className="menu-pointer menu-pointer-low" />
              </div>
              <h3>Approve it once</h3>
              <p>Double-click Kaeru and click <b>Done</b>. Then open <b>System Settings → Privacy &amp; Security</b>, scroll down and click <b>Open Anyway</b>.</p>
              <a href="/install" className="step-link">Step-by-step guide with pictures →</a>
            </li>
          </ol>
          <div className="install-alt">
            <span>Prefer Terminal? This does the same as Open Anyway:</span>
            <CopyCommand command="xattr -dr com.apple.quarantine /Applications/Kaeru.app" />
          </div>
        </section>

        <section id="formats" className="section">
          <h2>{totalConversions} ways to change a file</h2>
          <p className="section-lede">Images, video, audio, PDFs, Office documents, e-books, spreadsheets, subtitles and archives.</p>
          <div className="formats">
            {FORMAT_GROUPS.map((g) => (
              <div key={g.name} className="card format-card" style={{ "--accent": COLORS[g.category] } as React.CSSProperties}>
                <h3>{g.name}</h3>
                <div className="format-row"><span className="format-label">From</span>
                  <div className="chips">{g.inputs.map((x) => <span key={x} className="badge">{x}</span>)}</div></div>
                <div className="format-row"><span className="format-label">To</span>
                  <div className="chips">{g.outputs.map((x) => <span key={x} className="chip">{x}</span>)}</div></div>
              </div>
            ))}
          </div>
        </section>

        <section className="section">
          <h2>Better than uploading to a website</h2>
          <div className="card compare">
            <div className="compare-row compare-head"><span /><span>Kaeru</span><span>Online converters</span></div>
            {COMPARE.map(([label, us, them]) => (
              <div key={label} className="compare-row"><span>{label}</span><span className="us">{us}</span><span className="them">{them}</span></div>
            ))}
          </div>
        </section>

        {releases.length > 0 && (
          <section className="section">
            <h2>What&rsquo;s new</h2>
            <p className="section-lede">Kaeru updates itself. Here&rsquo;s what landed recently.</p>
            <div className="releases">
              {releases.map((r, i) => (
                <a key={r.version} href={r.url} className="card release">
                  <div className="release-head">
                    <span className="release-version">v{r.version}</span>
                    {i === 0 && <span className="release-latest">Latest</span>}
                    <span className="release-date">{r.date}</span>
                  </div>
                  <h3>{r.title}</h3>
                  <ul>{r.points.slice(0, 3).map((p) => <li key={p}>{p}</li>)}</ul>
                </a>
              ))}
            </div>
          </section>
        )}

        <section id="faq" className="section faq">
          <h2>Questions</h2>
          {FAQ.map((f) => (
            <details key={f.q} className="card">
              <summary>{f.q}</summary>
              <p>{f.a}</p>
            </details>
          ))}
        </section>

        <section className="final">
          <Image src="/shots/icon.png" alt="" width={96} height={96} />
          <h2>Less busywork. More <span className="maru grad">kaeru</span>.</h2>
          <a href={DOWNLOAD_URL} className="btn">Download Kaeru for free</a>
          <p className="meta">First launch: approve it once in Privacy &amp; Security — <a href="/install">here’s exactly how</a>. <a href={RELEASES_URL}>All releases</a></p>
        </section>
      </main>

      <footer className="footer">
        <span>© 2026 Kaeru · MIT licensed</span>
        <span>
          <a href={GITHUB_URL}>GitHub</a>
          <a href={`${GITHUB_URL}/issues/new`}>Report an issue</a>
          <a href={`${GITHUB_URL}/blob/main/LICENSE`}>License</a>
        </span>
      </footer>
    </>
  );
}
