#!/bin/bash
# Archive, sign and upload the current tree to TestFlight.
#
#   ./scripts/release-testflight.sh
#
# Exists because doing this by hand went wrong twice in one evening: the build
# number stayed pinned at 1 in project.yml (so a second upload would have been
# rejected as a duplicate), and it was easy to lose track of what had actually
# been *uploaded* versus merely installed on a device over USB. TestFlight only
# ever knows what was pushed to it.
#
# The build number is read from App Store Connect rather than stored anywhere:
# the server already knows the highest number it has accepted, so it is the only
# source that cannot drift. It is passed on the xcodebuild command line, leaving
# project.yml free of a value that would go stale the moment it is committed.
set -euo pipefail

APP_ID="${AVERT_APP_ID:-6794721645}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Outside iCloud: codesign fails on the xattrs iCloud adds (see CLAUDE.md).
WORK="${TMPDIR:-/tmp}/avert-release"
ARCHIVE="$WORK/Avert.xcarchive"
OPTIONS="$WORK/UploadExportOptions.plist"

mkdir -p "$WORK"
cd "$ROOT"

echo "▸ Bundles JS (typecheck + tests + garde réseau)"
./scripts/build-js.sh >/dev/null

BUILD_NUMBER="$(asc builds next-build-number --app "$APP_ID" --output json \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["nextBuildNumber"])')"
MARKETING="$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/')"
echo "▸ Version $MARKETING ($BUILD_NUMBER)"

echo "▸ Projet"
xcodegen generate >/dev/null

echo "▸ Archive"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project Avert.xcodeproj -scheme Avert \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/dd" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  >"$WORK/archive.log" 2>&1 || { tail -30 "$WORK/archive.log"; exit 1; }

echo "▸ Export et envoi"
asc xcode export-options generate --archive-path "$ARCHIVE" --destination upload \
  --output-path "$OPTIONS" --overwrite >/dev/null
# xcodebuild -exportArchive defaults manageAppVersionAndBuildNumber to YES and
# silently renumbers the build on upload. That is how build 1 became build 2
# without the archive changing — and it makes the archive on disk stop matching
# what shipped, which cost an evening of confusion. We set the number ourselves.
/usr/libexec/PlistBuddy -c "Add :manageAppVersionAndBuildNumber bool false" "$OPTIONS" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :manageAppVersionAndBuildNumber false" "$OPTIONS"
asc xcode export --archive-path "$ARCHIVE" --export-options "$OPTIONS" \
  --ipa-path "$WORK/Avert.ipa" --xcodebuild-flag=-allowProvisioningUpdates \
  >"$WORK/export.log" 2>&1 || { tail -20 "$WORK/export.log"; exit 1; }

echo "▸ Attente du traitement Apple"
BUILD_ID=""
for _ in $(seq 1 40); do
  BUILD_ID="$(asc builds list --app "$APP_ID" --output json 2>/dev/null | /usr/bin/python3 -c '
import json,sys
try: d = json.load(sys.stdin)
except Exception: raise SystemExit
for b in d.get("data", []):
    a = b["attributes"]
    if a.get("version") == "'"$BUILD_NUMBER"'" and a.get("processingState") == "VALID":
        print(b["id"]); break
')"
  [ -n "$BUILD_ID" ] && break
  sleep 30
done
[ -n "$BUILD_ID" ] || { echo "✗ build $BUILD_NUMBER toujours en traitement après 20 min"; exit 1; }

# Internal AND external, then submit for beta review. "Push TestFlight" means
# the build is actually testable by everyone it is meant for — leaving the
# public link pointing at an older build is a half-delivery.
echo "▸ Groupes de test"
for GROUP in $(asc testflight groups list --app "$APP_ID" --output json \
  | /usr/bin/python3 -c 'import json,sys; print(" ".join(g["id"] for g in json.load(sys.stdin)["data"]))'); do
  asc builds add-groups --build-id "$BUILD_ID" --group "$GROUP" >/dev/null 2>&1 || true
done

echo "▸ Soumission à la revue bêta (nécessaire au lien public)"
asc testflight review submit --build-id "$BUILD_ID" --confirm >/dev/null 2>&1 \
  && echo "  soumis" || echo "  déjà soumis ou refusé — vérifier avec: asc testflight review submissions"

echo "✓ $MARKETING ($BUILD_NUMBER) — interne disponible, public après revue"
