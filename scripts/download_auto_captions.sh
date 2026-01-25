#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <url-or-id> [output-dir]" >&2
  exit 2
fi

input="$1"
out_dir="${2:-.}"

if ! command -v yt-dlp >/dev/null 2>&1; then
  cat <<'MSG' >&2
yt-dlp is not installed.
Install options:
- macOS (Homebrew): brew install yt-dlp
- Python (pipx): pipx install yt-dlp
- Python (pip): python3 -m pip install -U yt-dlp
Then re-run this script.
MSG
  exit 127
fi

if [[ "$input" =~ ^https?:// ]]; then
  url="$input"
else
  url="https://www.youtube.com/watch?v=$input"
fi

mkdir -p "$out_dir"

yt-dlp \
  --skip-download \
  --write-auto-subs \
  --sub-lang en \
  --sub-format vtt \
  --paths "$out_dir" \
  "$url"

video_id=""
if [[ "$input" =~ ^https?:// ]]; then
  if [[ "$input" =~ v=([A-Za-z0-9_-]{11}) ]]; then
    video_id="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
    video_id="${BASH_REMATCH[1]}"
  fi
else
  video_id="$input"
fi

convert_vtt_to_txt() {
  local vtt_file="$1"
  local txt_file="$2"

  awk '
    BEGIN{IGNORECASE=1}
    function html_decode(s) {
      gsub(/&gt;/, ">", s)
      gsub(/&lt;/, "<", s)
      gsub(/&amp;/, "&", s)
      return s
    }
    {
      line=$0
      if (line ~ /^WEBVTT/ || line ~ /^Kind:/ || line ~ /^Language:/ || line ~ /^NOTE/) next
      if (line ~ /^[0-9]+$/) next
      if (line ~ /-->/) next

      line=html_decode(line)
      gsub(/<[0-9:.]+>/, "", line)
      gsub(/<[^>]+>/, "", line)
      sub(/^>>[[:space:]]*/, "", line)
      gsub(/\[[^]]*(music|singing|applause|laughter|cheering|cheers|instrumental)[^]]*\]/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

      if (line == "") next
      print line
    }
  ' "$vtt_file" | awk '
    function contains(a,b){ return index(a,b)>0 }
    {
      line=$0
      if (line == "") next
      if (prev == "") { prev=line; next }
      if (line == prev) next
      if (contains(line, prev)) { prev=line; next }
      if (contains(prev, line)) next
      print prev
      prev=line
    }
    END { if (prev != "") print prev }
  ' | awk '
    {
      line=$0
      if (line == "") {
        if (buf != "") { print buf; buf="" }
        next
      }
      if (buf == "") { buf=line; next }
      if (buf ~ /[.!?]["'\''"]?$/) {
        print buf
        buf=line
        next
      }
      buf = buf " " line
    }
    END { if (buf != "") print buf }
  ' > "$txt_file"
}

if [[ -n "$video_id" ]]; then
  shopt -s nullglob
  for vtt in "$out_dir"/*"$video_id"*.vtt; do
    txt="${vtt%.vtt}.txt"
    convert_vtt_to_txt "$vtt" "$txt"
  done
  shopt -u nullglob
else
  latest_vtt=""
  if ls -t "$out_dir"/*.vtt >/dev/null 2>&1; then
    latest_vtt=$(ls -t "$out_dir"/*.vtt | head -n 1)
  fi
  if [[ -n "$latest_vtt" ]]; then
    convert_vtt_to_txt "$latest_vtt" "${latest_vtt%.vtt}.txt"
  fi
fi
