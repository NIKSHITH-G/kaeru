import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { CopyCommand } from "../components/Bits";
import { DOWNLOAD_URL, GITHUB_URL } from "../site";
import "./install.css";

export const metadata: Metadata = {
  title: "Install Kaeru — step by step",
  description: "Exactly how to download Kaeru, approve it in Privacy & Security, and turn on its keyboard features.",
};

/* Drawings of the macOS windows you'll meet, with the thing to click highlighted. */

function DmgWindow() {
  return (
    <div className="mac-window">
      <div className="mac-titlebar"><span className="lights" />Kaeru</div>
      <div className="mac-dmg">
        <div className="mac-dmg-item"><Image src="/shots/icon.png" alt="" width={64} height={64} /><span>Kaeru</span></div>
        <div className="mac-dmg-arrow">→</div>
        <div className="mac-dmg-item"><span className="mac-folder" /><span>Applications</span></div>
      </div>
    </div>
  );
}

function NotOpenedAlert() {
  return (
    <div className="mac-alert">
      <Image src="/shots/icon.png" alt="" width={52} height={52} />
      <b>“Kaeru” Not Opened</b>
      <p>Apple could not verify “Kaeru” is free of malware that may harm your Mac or compromise your privacy.</p>
      <div className="mac-buttons">
        <span className="mac-btn">Move to Trash</span>
        <span className="mac-btn is-primary is-target">Done</span>
      </div>
    </div>
  );
}

function PrivacySecurity() {
  return (
    <div className="mac-window mac-settings">
      <div className="mac-titlebar"><span className="lights" />Privacy &amp; Security</div>
      <div className="mac-settings-body">
        <div className="mac-sidebar">
          {["Wi-Fi", "Bluetooth", "Network", "General", "Appearance", "Accessibility", "Privacy & Security", "Desktop & Dock"].map((s) => (
            <span key={s} className={s === "Privacy & Security" ? "is-selected" : ""}>{s}</span>
          ))}
        </div>
        <div className="mac-pane">
          <span className="mac-pane-dim">…scroll down past Privacy…</span>
          <h4>Security</h4>
          <div className="mac-row">
            <span>Allow applications from</span>
            <span className="mac-select">App Store &amp; Known Developers</span>
          </div>
          <div className="mac-row">
            <span>“Kaeru” was blocked to protect your Mac.</span>
            <span className="mac-btn is-target">Open Anyway</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function ConfirmOpen() {
  return (
    <div className="mac-alert">
      <Image src="/shots/icon.png" alt="" width={52} height={52} />
      <b>Open “Kaeru”?</b>
      <p>Apple is not able to verify that it is free from malware. Only open it if you trust where it came from.</p>
      <div className="mac-buttons">
        <span className="mac-btn is-primary is-target">Open Anyway</span>
        <span className="mac-btn">Done</span>
      </div>
      <small>macOS then asks for your password or Touch ID.</small>
    </div>
  );
}

function AccessibilityList() {
  return (
    <div className="mac-window mac-settings">
      <div className="mac-titlebar"><span className="lights" />Accessibility</div>
      <div className="mac-pane mac-pane-full">
        <span className="mac-pane-dim">Privacy &amp; Security › Accessibility</span>
        <p className="mac-caption">Allow the applications below to control your computer.</p>
        {[["Kaeru", true], ["Raycast", false], ["Zoom", false]].map(([name, target]) => (
          <div key={name as string} className="mac-row">
            <span className="mac-app">
              {target ? <Image src="/shots/icon.png" alt="" width={20} height={20} /> : <span className="mac-app-icon" />}
              {name}
            </span>
            <span className={`mac-toggle ${target ? "is-on is-target" : ""}`}><i /></span>
          </div>
        ))}
      </div>
    </div>
  );
}

function AutomationAlert() {
  return (
    <div className="mac-alert">
      <span className="mac-alert-glyph">⚙︎</span>
      <b>“Kaeru” wants access to control “Finder”.</b>
      <p>Allowing control will provide access to documents and data in “Finder”, and to perform actions within that app.</p>
      <div className="mac-buttons">
        <span className="mac-btn">Don’t Allow</span>
        <span className="mac-btn is-primary is-target">Allow</span>
      </div>
    </div>
  );
}

const STEPS: { title: string; body: React.ReactNode; art?: React.ReactNode }[] = [
  {
    title: "Download Kaeru",
    body: <>Click <a href={DOWNLOAD_URL}><b>Download Kaeru.dmg</b></a>. Your browser saves it in your <b>Downloads</b> folder (about 20 MB).</>,
  },
  {
    title: "Open the download",
    body: <>Open <b>Downloads</b> (in the Dock, or Finder → <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>) and <b>double-click Kaeru.dmg</b>. A small window opens showing Kaeru and an Applications folder.</>,
    art: <DmgWindow />,
  },
  {
    title: "Drag Kaeru into Applications",
    body: <><b>Drag the frog icon onto the Applications folder</b> in that window. Then close the window and eject the disk: click <b>⏏</b> next to “Kaeru” in Finder’s sidebar.</>,
  },
  {
    title: "Open Kaeru for the first time",
    body: <>Open your <b>Applications</b> folder (Finder → <kbd>⇧</kbd><kbd>⌘</kbd><kbd>A</kbd>) and <b>double-click Kaeru</b>. macOS shows “Kaeru” Not Opened, because Kaeru isn’t signed with a paid Apple certificate yet. <b>Click Done</b> — not Move to Trash.</>,
    art: <NotOpenedAlert />,
  },
  {
    title: "Open System Settings → Privacy & Security",
    body: <>Click the <b> Apple menu</b> (top-left of the screen) → <b>System Settings…</b> In the sidebar, click <b>Privacy &amp; Security</b>. Scroll all the way down to the <b>Security</b> section.</>,
  },
  {
    title: "Click Open Anyway",
    body: <>Next to <b>“Kaeru” was blocked to protect your Mac.</b>, click <b>Open Anyway</b>. (This button only appears for about an hour after step 4 — if it’s missing, double-click Kaeru again, then come back.)</>,
    art: <PrivacySecurity />,
  },
  {
    title: "Confirm",
    body: <>In the dialog that appears, click <b>Open Anyway</b> again, then enter your <b>Mac password</b> or use <b>Touch ID</b>. Kaeru opens, the 🐸 appears in your menu bar, and the tutorial starts. You only do this once — updates install without it.</>,
    art: <ConfirmOpen />,
  },
  {
    title: "Turn on keyboard features (recommended)",
    body: <>In the tutorial, click <b>Allow Keyboard Access…</b> → <b>Open System Settings</b>. macOS opens <b>Privacy &amp; Security → Accessibility</b>: <b>switch on Kaeru</b> and confirm with your password. This enables <b>Return in Finder</b> and the Tab trigger. Kaeru picks it up within two seconds — no restart.</>,
    art: <AccessibilityList />,
  },
  {
    title: "Allow Finder access when asked",
    body: <>The first time you press Return in Finder (or <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd>), macOS asks whether Kaeru may control Finder. <b>Click Allow</b> — Kaeru uses it only to read which files you selected. Converting slides asks the same for PowerPoint or Keynote.</>,
    art: <AutomationAlert />,
  },
];

export default function InstallPage() {
  return (
    <main className="install">
      <Link href="/" className="install-back">← Kaeru</Link>
      <header className="install-head">
        <Image src="/shots/icon.png" alt="" width={72} height={72} />
        <h1>Install Kaeru, step by step</h1>
        <p>About two minutes. Works on Apple silicon Macs with macOS 13 or later.</p>
        <a href={DOWNLOAD_URL} className="btn">Download Kaeru.dmg</a>
      </header>

      <ol className="install-steps">
        {STEPS.map((s, i) => (
          <li key={s.title} className="install-step">
            <span className="install-n">{i + 1}</span>
            <div className="install-text">
              <h2>{s.title}</h2>
              <p>{s.body}</p>
            </div>
            {s.art && <div className="install-art">{s.art}</div>}
          </li>
        ))}
      </ol>

      <section className="install-help">
        <h2>If something doesn’t go to plan</h2>
        <details className="card" open>
          <summary>On macOS 13 Ventura or 14 Sonoma</summary>
          <p>Instead of steps 5–7 you can <b>right-click (or Control-click) Kaeru</b> in Applications, choose <b>Open</b>, then click <b>Open</b> in the dialog.</p>
        </details>
        <details className="card">
          <summary>“Kaeru is damaged and can’t be opened”</summary>
          <p>That’s the same first-launch check, shown differently. Open <b>Terminal</b> (Applications → Utilities → Terminal), paste this line, press <kbd>Return</kbd>, then open Kaeru again:</p>
          <CopyCommand command="xattr -dr com.apple.quarantine /Applications/Kaeru.app" />
        </details>
        <details className="card">
          <summary>There’s no Open Anyway button</summary>
          <p>It appears only after you’ve tried to open Kaeru, and disappears after about an hour. Double-click Kaeru in Applications again, click <b>Done</b>, then go straight back to <b>System Settings → Privacy &amp; Security</b> and scroll to the bottom.</p>
        </details>
        <details className="card">
          <summary>Return in Finder stopped working</summary>
          <p>Open <b>System Settings → Privacy &amp; Security → Accessibility</b>, switch Kaeru <b>off and on again</b>. If Kaeru isn’t listed, click <b>+</b>, choose Kaeru from Applications, and switch it on.</p>
        </details>
        <details className="card">
          <summary>I don’t see the frog in the menu bar</summary>
          <p>Kaeru lives only in the menu bar — it has no Dock icon. Open it again from Applications. If your menu bar is crowded, the frog may be hidden behind the notch: try quitting another menu bar app.</p>
        </details>
        <details className="card">
          <summary>Uninstall</summary>
          <p>Click the 🐸 → <b>Quit Kaeru</b>, drag Kaeru from Applications to the Trash, and remove it from <b>Privacy &amp; Security → Accessibility</b> (select it, click <b>−</b>).</p>
        </details>
        <p className="install-foot">Still stuck? <a href={`${GITHUB_URL}/issues/new`}>Open an issue on GitHub</a> and we’ll help.</p>
      </section>
    </main>
  );
}
