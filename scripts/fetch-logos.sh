#!/bin/bash
# Fetch a brand's own logo assets so `hash-logos.ts` can turn them into dHash
# references (registry/README.md).
#
#   ./scripts/fetch-logos.sh <domaine> <dossier-de-sortie>
#
# Development-time only: the app never makes a network request, and only the
# 64-bit hashes are committed — no brand image ships in the bundle.
#
# What it collects, in order of usefulness for the signal:
#   1. <img> tags whose class/alt/id/src mentions logo or brand — this is what a
#      phishing kit copies, and what `logo.ts` hashes on the page.
#   2. apple-touch-icon / og:image as a fallback.
# Only same-origin assets, mirroring the extension's constraint.
#
# SVG is converted with rsvg-convert: sips cannot decode it, and a good share of
# brand logos are vector.
set -euo pipefail

DOMAIN="${1:?usage: fetch-logos.sh <domaine> <dossier>}"
OUT="${2:?usage: fetch-logos.sh <domaine> <dossier>}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

mkdir -p "$OUT"
HTML="$OUT/.page.html"

if ! curl -sSL --max-time 20 -A "$UA" "https://$DOMAIN/" -o "$HTML" 2>/dev/null; then
  echo "  ✗ $DOMAIN : page inaccessible"
  exit 0
fi

# Extract candidate asset URLs from the markup. grep -o over the raw HTML rather
# than a parser: no dependency, and we only need attribute values.
#
# Every grep is `|| true`: with `set -e` and `pipefail`, a grep that simply finds
# nothing killed the script before it reported anything — which is why the first
# run looked like six sites were unreachable when they were merely logo-less.
# Only <img> tags that name themselves a logo. apple-touch-icon and og:image were
# tried and dropped: the first is a rounded app icon and the second a marketing
# banner, so neither is the mark a kit copies — and hashing them would let an
# unrelated product photo stand in as "Apple's logo", the exact false positive
# this signal must not create.
{
  (grep -oiE '<img[^>]+>' "$HTML" || true) | (grep -iE 'logo|brand' || true) \
    | (grep -oiE 'src="[^"]+"' || true) | cut -d'"' -f2
} 2>/dev/null | sort -u | head -6 > "$OUT/.candidates" || true

# Inline <svg> is now the common way to ship a logo, and it has no URL to fetch.
# Pull out any inline SVG sitting inside a logo-ish element and rasterise it.
uv run --no-project python - "$HTML" "$OUT" "$DOMAIN" <<'PY' || true
import re, sys, pathlib
html = pathlib.Path(sys.argv[1]).read_text(errors="replace")
out, domain = pathlib.Path(sys.argv[2]), sys.argv[3]
stem = domain.replace(".", "_")
# Keep SVGs that look like a mark: a logo-ish attribute nearby, bounded size.
found = 0
for m in re.finditer(r"<svg\b[^>]*>.*?</svg>", html, re.S | re.I):
    svg = m.group(0)
    context = html[max(0, m.start() - 220):m.start()] + svg[:220]
    if not re.search(r"logo|brand", context, re.I):
        continue
    if len(svg) > 200_000:
        continue
    found += 1
    if "xmlns" not in svg:
        svg = svg.replace("<svg", '<svg xmlns="http://www.w3.org/2000/svg"', 1)
    (out / f"{stem}-inline{found}.svg").write_text(svg)
    if found >= 3:
        break
PY

n=0
while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  case "$ref" in
    data:*) continue ;;                       # inline, nothing to fetch
    //*)  url="https:$ref" ;;
    /*)   url="https://$DOMAIN$ref" ;;
    http*) url="$ref" ;;
    *)    url="https://$DOMAIN/$ref" ;;
  esac

  # Same-origin only, like the extension: a third-party CDN asset is covered by
  # the URL-based signal instead.
  host=$(printf '%s' "$url" | sed -E 's|^https?://([^/]+).*|\1|')
  case "$host" in
    *"$DOMAIN") ;;
    *) continue ;;
  esac

  ext="${url##*.}"; ext="${ext%%\?*}"
  case "$(printf '%s' "$ext" | tr 'A-Z' 'a-z')" in
    png|jpg|jpeg|svg|webp) ;;
    *) ext="png" ;;
  esac

  n=$((n + 1))
  raw="$OUT/$(printf '%s' "$DOMAIN" | tr '.' '_')-$n.$ext"
  curl -sSL --max-time 15 -A "$UA" -e "https://$DOMAIN/" "$url" -o "$raw" 2>/dev/null || continue
  [ -s "$raw" ] || { rm -f "$raw"; continue; }

  if [ "$ext" = "svg" ]; then
    # Rasterise at a generous size: the hash box-averages down anyway, and a
    # tiny raster would lose the structure the hash encodes.
    if rsvg-convert -w 512 "$raw" -o "${raw%.svg}.png" 2>/dev/null; then
      rm -f "$raw"
    else
      rm -f "$raw"
      continue
    fi
  fi
done < "$OUT/.candidates"

# Rasterise whatever inline SVG the python step wrote.
for svg in "$OUT/$(printf '%s' "$DOMAIN" | tr '.' '_')"-inline*.svg; do
  [ -e "$svg" ] || continue
  rsvg-convert -w 512 "$svg" -o "${svg%.svg}.png" 2>/dev/null || true
  rm -f "$svg"
done

rm -f "$HTML" "$OUT/.candidates"
found=$(find "$OUT" -maxdepth 1 -name "$(printf '%s' "$DOMAIN" | tr '.' '_')-*" | wc -l | tr -d ' ')
echo "  $DOMAIN : $found fichier(s)"
