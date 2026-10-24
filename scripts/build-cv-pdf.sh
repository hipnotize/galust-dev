#!/usr/bin/env bash
# Prints the standalone CV pages of a built site (English and Russian) to PDF
# and fails if either runs past two pages.
# Usage: scripts/build-cv-pdf.sh [public-dir]
set -euo pipefail

public="${1:-public}"

chrome="${CHROME:-}"
if [ -z "$chrome" ]; then
  for c in google-chrome google-chrome-stable chromium "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then chrome="$c"; break; fi
  done
fi
[ -n "$chrome" ] || { echo "Chrome not found, set CHROME=/path/to/chrome" >&2; exit 1; }

render() {  # render <print page> <output pdf>
  local page="$public/$1" out="$public/$2"
  [ -f "$page" ] || { echo "No $page: build the site first" >&2; exit 1; }
  local uri pages
  uri=$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$page")
  "$chrome" --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$out" "$uri" 2>/dev/null
  pages=$(python3 -c 'import re, sys; print(len(re.findall(rb"/Type\s*/Page[^s]", open(sys.argv[1], "rb").read())))' "$out")
  echo "CV PDF: $out, $pages page(s)"
  [ "$pages" -ge 1 ] && [ "$pages" -le 2 ] || { echo "CV must be 1-2 pages, got $pages" >&2; exit 1; }
}

render cv/print/index.html    cv/Galust_Arakelyan_DevOps.pdf
render ru/cv/print/index.html ru/cv/Galust_Arakelyan_DevOps_RU.pdf
