#!/bin/bash
# Render every icon Avert ships, from the two canonical SVGs.
#
#   ./scripts/render-icons.sh
#
# One script because the same mark appears in four places with four different
# rules, and keeping them in step by hand already failed once (the in-app mark
# drifted from the Home Screen icon and it was visible side by side).
#
#   design/AppIcon.svg     → app icon        square, NO alpha (App Store rule)
#                          → extension icons ROUNDED, alpha kept
#   design/ActionIcon.svg  → action icon     silhouette, alpha = the whole point
#
# The rounding matters: Safari lists web-extension icons from manifest.json
# as-is, with no mask of its own. A full-bleed square sits among a column of
# rounded icons looking broken — which is exactly how it shipped first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export TMPDIR="${TMPDIR:-/tmp}"

# Apple's icon grid: corner radius ≈ 22.37 % of the side. Not a true squircle —
# a rounded rectangle is indistinguishable at these sizes and needs no path math.
radius_for() { echo "scale=0; $1 * 2237 / 10000" | bc; }

round() { # round <png> — clip to the icon shape in place
  local f="$1" w r
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  r=$(radius_for "$w")
  magick "$f" \
    \( -size "${w}x${w}" xc:none -draw "roundrectangle 0,0,$((w - 1)),$((w - 1)),$r,$r" \) \
    -alpha set -compose DstIn -composite "$f"
}

echo "▸ Icône de l'app (1024, sans alpha — exigence App Store)"
rsvg-convert -w 1024 -h 1024 design/AppIcon.svg -o App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
if [ "$(sips -g hasAlpha App/Assets.xcassets/AppIcon.appiconset/icon-1024.png | awk '/hasAlpha/{print $2}')" = "yes" ]; then
  echo "  ✗ canal alpha présent : l'App Store refuserait" >&2
  exit 1
fi

echo "▸ Icônes de l'extension Safari (arrondies)"
for s in 48 96 128 256 512; do
  out="Extension/Resources/images/icon-$s.png"
  rsvg-convert -w "$s" -h "$s" design/AppIcon.svg -o "$out"
  round "$out"
done

echo "▸ Icône de l'extension d'action (silhouette, alpha conservé)"
for s in 40 58 60 80 87 120 152 167 180 1024; do
  rsvg-convert -w "$s" -h "$s" design/ActionIcon.svg \
    -o "ActionExtension/Assets.xcassets/AppIcon.appiconset/icon-$s.png"
done

echo "✓ Icônes régénérées"
