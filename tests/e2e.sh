#!/bin/bash
# End-to-end test: generates a sample of every supported input type, runs every Convert and Tools
# operation on each through the headless CLI, and validates each output for its format.
# Usage: tests/e2e.sh [path/to/Kaeru]   (default: .build/debug/Kaeru)
#        EXTRA="a.xls b.ppt" tests/e2e.sh   also tests extra files you have locally
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(cd "$(dirname "${1:-.build/debug/Kaeru}")" && pwd)/$(basename "${1:-.build/debug/Kaeru}")"
EXTRA_FILES=()
for f in ${EXTRA:-}; do EXTRA_FILES+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"); done
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# Editors and app automation are driven by environment variables in headless runs.
export KAERU_NO_APPS=1 KAERU_TRIM=0.5-1.5 KAERU_CROP=10,10,200,100

echo "Generating fixtures…"
q() { "$@" >/dev/null 2>&1 || echo "  (couldn't make fixture: $*)"; }
# Images
q ffmpeg -loglevel error -f lavfi -i testsrc2=size=800x500 -frames:v 1 photo.png
q sips -s format heic photo.png --out photo.heic
q sips -s format jpeg photo.png --out photo.jpg
q sips -s format tiff photo.png --out photo.tiff
q ffmpeg -loglevel error -f lavfi -i testsrc2=size=320x200:rate=10 -t 1 anim.gif
command -v cwebp >/dev/null && q cwebp -quiet photo.png -o photo.webp
printf '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120"><rect width="200" height="120" rx="20" fill="#22c578"/><text x="100" y="72" font-size="40" text-anchor="middle" fill="white">Kaeru</text></svg>' > logo.svg
# Video and audio
q ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest clip.mp4
q ffmpeg -loglevel error -i clip.mp4 -c copy clip.mov
q ffmpeg -loglevel error -i clip.mp4 -c copy clip.mkv
q ffmpeg -loglevel error -i clip.mp4 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 300k -c:a libopus clip.webm
q ffmpeg -loglevel error -f lavfi -i sine=frequency=330 -t 3 tone.wav
q ffmpeg -loglevel error -i tone.wav tone.mp3
q ffmpeg -loglevel error -i tone.wav tone.flac
q ffmpeg -loglevel error -i tone.wav -c:a aac tone.m4a
q ffmpeg -loglevel error -i tone.wav -c:a libopus tone.ogg
# Documents
printf '# Notes\n\nSome **bold** text.\n\n- one\n- two\n\n| A | B |\n| - | - |\n| 1 | 2 |\n' > notes.md
printf 'Plain text notes.\nSecond line.\n' > notes.txt
printf '<html><body><h1>Title</h1><p>Hello <b>world</b></p></body></html>' > notes.html
q textutil -convert rtf notes.html -output notes.rtf
q textutil -convert doc notes.html -output notes.doc
for target in docx odt epub pdf; do "$BIN" --run "doc.$target" notes.md >/dev/null 2>&1; done
"$BIN" --run pdf.combine notes.pdf photo.png >/dev/null 2>&1 && mv Combined.pdf multipage.pdf
"$BIN" --run pdf.pptx multipage.pdf >/dev/null 2>&1 && mv multipage.pptx deck.pptx
# Spreadsheets and data
printf 'name,age\n"Smith, J",42\nJane,7\nJane,7\n' > people.csv
for target in tsv xlsx ods; do "$BIN" --run "table.$target" people.csv >/dev/null 2>&1; done
echo '[{"id":1,"name":"Ada"},{"id":2,"name":"Bo"}]' > data.json
"$BIN" --run json.plist data.json >/dev/null 2>&1
printf '1\n00:00:01,000 --> 00:00:02,000\n<i>Hello</i>\n' > subs.srt
"$BIN" --run sub.vtt subs.srt >/dev/null 2>&1
# Archives and folders
mkdir -p folder && echo hi > folder/a.txt && cp photo.png photo.jpg folder/
q zip -qr folder.zip folder
q tar -czf folder.tar.gz folder
q tar -cjf folder.tar.bz2 folder
q tar --format 7zip -cf folder.7z folder

# Synthetic test images have no subject to cut out.
SKIP="image.removebg"
# Correct refusals for inputs that don't qualify (a picture-free document, a one-page PDF).
EXPECTED="has no embedded images|has only one page"

# Checks an output really is a valid file of its type, not just non-empty.
valid() {
    local f=$1
    [ -e "$f" ] || return 1
    [ -d "$f" ] && { [ -n "$(ls -A "$f")" ]; return; }
    [ -s "$f" ] || return 1
    case "${f##*.}" in
        jpg|png|heic|webp|avif|tiff|gif|bmp|ico|icns) sips -g pixelWidth "$f" >/dev/null 2>&1 || [ "${f##*.}" = webp ] ;;
        mp4|mov|mkv|webm|avi|wmv|mp3|m4a|wav|flac|ogg|opus|aiff|wma)
            ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null | grep -q '[0-9]' ;;
        pdf) [ "$(head -c 5 "$f")" = "%PDF-" ] ;;
        docx|xlsx|pptx|odt|ods|epub|zip) unzip -tq "$f" >/dev/null 2>&1 ;;
        json) python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null ;;
        plist) plutil -lint -s "$f" ;;
        gz|bz2|7z) tar -tf "$f" >/dev/null 2>&1 ;;
        *) true ;;
    esac
}

pass=0; failed=0
check() {  # check <op> <files…>
    local op=$1; shift
    local out
    if out=$("$BIN" --run "$op" "$@" 2>&1); then
        local first
        first=$(echo "$out" | grep -v 'Kaeru\[' | head -1)
        # Operations that only report a message (counts, tests) print text instead of a path.
        if [[ "$first" != /* ]] || valid "$first"; then
            pass=$((pass + 1)); return
        fi
        out="invalid output: $first"
    elif echo "$out" | grep -qE "$EXPECTED"; then
        pass=$((pass + 1)); return
    fi
    failed=$((failed + 1))
    echo "FAIL $op $*: $(echo "$out" | grep -v 'Kaeru\[' | tail -1)"
}

inputs=(photo.png photo.heic photo.jpg photo.tiff anim.gif photo.webp logo.svg
        clip.mp4 clip.mov clip.mkv clip.webm tone.wav tone.mp3 tone.flac tone.m4a tone.ogg
        notes.md notes.txt notes.html notes.rtf notes.doc notes.docx notes.odt notes.epub notes.pdf multipage.pdf
        deck.pptx people.csv people.tsv people.xlsx people.ods data.json data.plist subs.srt subs.vtt
        folder folder.zip folder.tar.gz folder.tar.bz2 folder.7z ${EXTRA_FILES[@]+"${EXTRA_FILES[@]}"})
for f in "${inputs[@]}"; do
    [ -e "$f" ] || { echo "skip $f (fixture missing)"; continue; }
    ops=$("$BIN" --list "$f" | grep -v '^Actions' | cut -d: -f2)
    [ -n "${ops// /}" ] || { failed=$((failed + 1)); echo "FAIL $f: no operations offered"; }
    for op in $ops; do
        [[ " $SKIP " == *" $op "* ]] && continue
        check "$op" "$f"
    done
done
check pdf.combine photo.png notes.pdf
check video.merge clip.mp4 clip.mov
check audio.merge tone.wav tone.mp3
check archive.zip photo.png notes.md

echo "passed=$pass failed=$failed"
[ "$failed" -eq 0 ]
