"use client";

import { Check, Copy, Monitor } from "lucide-react";
import { useEffect, useState } from "react";

/** A one-line shell command with a copy button. */
export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="copy-command">
      <code>{command}</code>
      <button
        onClick={() => {
          navigator.clipboard.writeText(command);
          setCopied(true);
          setTimeout(() => setCopied(false), 1600);
        }}
        aria-label="Copy command"
      >
        {copied ? <Check size={15} /> : <Copy size={15} />}
      </button>
    </div>
  );
}

/** Tells visitors on phones, tablets and PCs that Kaeru is a Mac app. */
export function PlatformNote() {
  const [platform, setPlatform] = useState<string | null>(null);
  useEffect(() => {
    const ua = navigator.userAgent;
    const touchMac = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;  // iPadOS reports itself as a Mac
    const name = /iPhone|iPod/.test(ua) ? "iPhone" : /iPad/.test(ua) || touchMac ? "iPad" : /Android/.test(ua) ? "Android"
      : /Windows/.test(ua) ? "Windows" : /Linux/.test(ua) ? "Linux" : null;
    // Reading the user agent has to wait until after hydration.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPlatform(name);
  }, []);
  if (!platform) return null;
  return (
    <p className="platform-note">
      <Monitor size={15} /> Kaeru is a Mac app. You&rsquo;re on {platform}, so open this page on your Mac to download it.
    </p>
  );
}
