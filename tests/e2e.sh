#!/bin/bash
# End-to-end test: generates sample files, runs every operation on each through the headless CLI,
# and checks each run succeeds and produces non-empty output.
# Usage: tests/e2e.sh [path/to/Kaeru]   (default: .build/debug/Kaeru)
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(cd "$(dirname "${1:-.build/debug/Kaeru}")" && pwd)/$(basename "${1:-.build/debug/Kaeru}")"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# Editors and app automation are driven by environment variables in headless runs.
export KAERU_NO_APPS=1 KAERU_TRIM=0.5-1.5 KAERU_CROP=10,10,200,100

echo "Generating fixtures…"
ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 2 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest clip.mp4
ffmpeg -loglevel error -f lavfi -i sine=frequency=330 -t 3 tone.wav
ffmpeg -loglevel error -f lavfi -i testsrc2=size=800x500 -frames:v 1 photo.png
sips -s format heic photo.png --out photo.heic >/dev/null
printf '# Notes\n\nSome **bold** text.\n\n- one\n- two\n\n| A | B |\n| - | - |\n| 1 | 2 |\n' > notes.md
printf 'name,age\n"Smith, J",42\nJane,7\n' > people.csv
echo '[{"id":1,"name":"Ada"},{"id":2,"name":"Bo"}]' > data.json
printf '1\n00:00:01,000 --> 00:00:02,000\nHello\n' > subs.srt
mkdir -p folder && echo hi > folder/a.txt
"$BIN" --run doc.docx notes.md >/dev/null
"$BIN" --run doc.pdf notes.md >/dev/null
"$BIN" --run doc.epub notes.md >/dev/null
"$BIN" --run table.ods people.csv >/dev/null
"$BIN" --run table.xlsx people.csv >/dev/null

# Expected failures on synthetic input.
SKIP="image.removebg pdf.split"

pass=0; failed=0
check() {  # check <op> <files…>
    local op=$1; shift
    local out
    if out=$("$BIN" --run "$op" "$@" 2>&1); then
        local first
        first=$(echo "$out" | grep -v 'Kaeru\[' | head -1)
        if [ -n "$first" ] && { [ -s "$first" ] || [ -d "$first" ] || [ ! -e "$first" ]; }; then
            pass=$((pass + 1)); return
        fi
    fi
    failed=$((failed + 1))
    echo "FAIL $op $*: $(echo "$out" | grep -v 'Kaeru\[' | tail -1)"
}

for f in clip.mp4 tone.wav photo.png photo.heic notes.md notes.docx notes.pdf notes.epub people.csv people.ods \
         people.xlsx data.json subs.srt folder; do
    for op in $("$BIN" --list "$f" | grep -v '^Actions' | cut -d: -f2); do
        [[ " $SKIP " == *" $op "* ]] && continue
        check "$op" "$f"
    done
done
check pdf.combine photo.png notes.pdf
check video.merge clip.mp4 clip.mp4
check audio.merge tone.wav tone.wav
check archive.zip photo.png notes.md

echo "passed=$pass failed=$failed"
[ "$failed" -eq 0 ]
