#!/usr/bin/env python3
"""Copies ffmpeg, ffprobe and cwebp from Homebrew into Kaeru.app, with every non-system dylib
they load, and rewrites library paths so the app runs on Macs without Homebrew.

Usage: scripts/bundle_helpers.py build/Kaeru.app

Layout:  Contents/Resources/bin/<tool>   Contents/Frameworks/<lib>.dylib
All references become @executable_path/../../Frameworks/<lib>, since the tools are the executables.
"""
import os
import re
import shutil
import subprocess
import sys

TOOLS = ["ffmpeg", "ffprobe", "cwebp"]
SEARCH = ["/opt/homebrew/bin", "/usr/local/bin"]
LIB_REF = "@executable_path/../../Frameworks/"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def dependencies(path):
    """Library references from `otool -L`, minus the file's own install name."""
    lines = run("otool", "-L", path).splitlines()[1:]
    refs = [line.strip().split(" (")[0] for line in lines]
    own = run("otool", "-D", path).splitlines()[1:]
    return [r for r in refs if r not in own]


def rpaths(path):
    out = run("otool", "-l", path)
    return re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", out)


def resolve(ref, referrer):
    """Absolute path for a Homebrew reference, or None for system libraries."""
    origin = os.path.dirname(os.path.realpath(referrer))
    if ref.startswith("@rpath/"):
        for rp in rpaths(referrer):
            candidate = os.path.join(rp.replace("@loader_path", origin).replace("@executable_path", origin), ref[7:])
            if os.path.exists(candidate):
                return os.path.realpath(candidate)
        return None
    if ref.startswith("@loader_path/"):
        return os.path.realpath(os.path.join(origin, ref[13:]))
    if ref.startswith(("/opt/homebrew/", "/usr/local/")):
        return os.path.realpath(ref)
    return None


def main(app):
    bin_dir = os.path.join(app, "Contents/Resources/bin")
    fw_dir = os.path.join(app, "Contents/Frameworks")
    os.makedirs(bin_dir, exist_ok=True)
    os.makedirs(fw_dir, exist_ok=True)

    queue = []  # (bundled copy, original location)
    for tool in TOOLS:
        source = next((os.path.join(d, tool) for d in SEARCH if os.path.exists(os.path.join(d, tool))), None)
        if not source:
            print(f"skip {tool}: not installed")
            continue
        dest = os.path.join(bin_dir, tool)
        shutil.copy2(os.path.realpath(source), dest)
        queue.append((dest, os.path.realpath(source)))

    seen = {}
    while queue:
        copy, original = queue.pop()
        os.chmod(copy, 0o755)
        for ref in dependencies(copy):
            lib = resolve(ref, original)
            if not lib:
                continue
            name = os.path.basename(lib)
            if name not in seen:
                dest = os.path.join(fw_dir, name)
                shutil.copy2(lib, dest)
                os.chmod(dest, 0o755)
                run("install_name_tool", "-id", LIB_REF + name, dest)
                seen[name] = dest
                queue.append((dest, lib))
            run("install_name_tool", "-change", ref, LIB_REF + name, copy)

    for path in [os.path.join(bin_dir, t) for t in os.listdir(bin_dir)] + list(seen.values()):
        subprocess.run(["codesign", "--force", "--sign", "-", path], check=True, capture_output=True)

    size = sum(os.path.getsize(os.path.join(d, f)) for d in (bin_dir, fw_dir) for f in os.listdir(d))
    print(f"Bundled {len(os.listdir(bin_dir))} tools and {len(seen)} libraries ({size / 1e6:.0f} MB)")


if __name__ == "__main__":
    main(sys.argv[1])
