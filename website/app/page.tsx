import Image from "next/image";
import WheelDemo from "./components/WheelDemo";
import { COLORS, DOWNLOAD_URL, FORMAT_GROUPS, GITHUB_URL, RELEASES_URL, latestRelease } from "./site";

const WHEELS = [
  { key: "⇧", name: "Convert", color: COLORS.brand,
    body: "Every format your file can become, in one ring. HEIC → JPG, MOV → MP4, DOCX → PDF, PDF → PPTX.",
    chips: ["JPG", "MP4", "PDF", "WebP", "MP3", "XLSX", "EPUB"] },
  { key: "⌘", name: "Tools", color: COLORS.tool,
    body: "Edit without an editor: trim and crop, compress, merge clips, remove backgrounds, pull text out of images.",
    chips: ["Trim", "Crop", "Compress", "Remove BG", "OCR", "Merge"] },
  { key: "⌃", name: "Actions", color: COLORS.action,
    body: "Things you do with files: AirDrop them, float them above every window, copy the path, open Terminal there.",
    chips: ["AirDrop", "Float", "Copy Path", "Move To", "Terminal"] },
];

const FEATURES = [
  { icon: "↩", title: "Return in Finder", body: "Select files and press Return — the wheel opens, no drag needed. Renaming still works." },
  { icon: "✂︎", title: "Trim & crop built in", body: "A QuickTime-style trimmer and a crop tool with aspect presets, opened right from the wheel." },
  { icon: "✦", title: "On-device AI", body: "Remove backgrounds, recognise text and make scanned PDFs searchable — with Apple's Vision, offline." },
  { icon: "◔", title: "See what's happening", body: "Live progress, one-click cancel, and a record of how much space compression saved." },
  { icon: "⟳", title: "Updates itself", body: "New versions install from inside the app. No App Store, no account." },
  { icon: "⌘", title: "Your keys, your way", body: "Pick Shift, ⌘, ⌃, ⌥, fn or Tab for each wheel. Keyboard-only control with arrows and Return." },
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
  { q: "Why does macOS warn me the first time I open it?", a: "Kaeru isn't signed with a paid Apple Developer certificate yet. Right-click Kaeru in Applications, choose Open, then Open again — you only do this once." },
  { q: "Does it upload my files?", a: "Never. Every conversion runs on your Mac using Apple's frameworks and a bundled FFmpeg. The only network request is an optional daily update check against GitHub." },
  { q: "Which Macs does it run on?", a: "Apple silicon Macs with macOS 13 Ventura or later. Background removal needs macOS 14." },
  { q: "I already use Shift for another drag tool.", a: "Change the key for any wheel in Settings — ⌥ Option, fn and Tab are all available." },
  { q: "What about PowerPoint and Pages files?", a: "Slides convert with PowerPoint or Keynote if installed, and with a built-in renderer otherwise. Pages documents use the Pages app." },
];

export default async function Home() {
  const release = await latestRelease();
  const totalConversions = 351;

  return (
    <>
      <header className="nav">
        <a href="#" className="brand"><Image src="/shots/icon.png" alt="" width={30} height={30} priority />Kaeru</a>
        <nav>
          <a href="#how">How it works</a>
          <a href="#formats">Formats</a>
          <a href="#faq">FAQ</a>
          <a href={GITHUB_URL} className="nav-gh">GitHub</a>
          <a href={DOWNLOAD_URL} className="btn btn-small">Download</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <p className="eyebrow"><span className="maru">かえる</span> · “to change” — and “frog”</p>
          <h1>Change any file.<br /><span className="grad">Without opening anything.</span></h1>
          <p className="lede">
            Drag a file, hold <kbd>⇧</kbd>, drop it on what you want. Kaeru turns every drag into a converter, editor
            and share menu — and never uploads a byte.
          </p>
          <div className="cta">
            <a href={DOWNLOAD_URL} className="btn">
              <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden><path fill="currentColor" d="M8 1v9.6l3.3-3.3 1.4 1.4L8 13.4 3.3 8.7l1.4-1.4L7 10.6V1h2zM2 14h12v2H2z" /></svg>
              Download for macOS
            </a>
            <a href={GITHUB_URL} className="btn btn-ghost">View source</a>
          </div>
          <p className="meta">
            Free · Open source · macOS 13+ · Apple silicon
            {release.version && <> · v{release.version}</>}
            {release.sizeMB && <> · {release.sizeMB} MB</>}
          </p>
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
                <span className="feature-icon">{f.icon}</span>
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
          <p className="meta">Then right-click → Open the first time. <a href={RELEASES_URL}>All releases</a></p>
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
