#!/bin/bash
# Every bundle that decides something must carry the data it decides with.
#
#   ./scripts/check-bundled-resources.sh <chemin/vers/Xxx.app ou .xcarchive>
#
# Exists because the app shipped without registry/brands.json while containing
# CheckLinkIntent, which calls LinkChecker, which reads BrandRegistry.shared.
# The registry loaded empty and every link checked from Siri, Spotlight or
# Shortcuts came back "nothing found" — the most reassuring verdict possible,
# on a tool whose whole job is to be suspicious.
#
# Nothing caught it: it compiles, and the unit tests inject their own registry
# precisely so they don't depend on the bundle. The warning comment was even
# already written in project.yml — but on one target only, and the apps were
# missed. So this checks the artifact, like check-no-network.sh does, because
# that is the only place the mistake is visible.
set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
  echo "usage: $0 <Xxx.app | Xxx.xcarchive>" >&2
  exit 2
fi

REQUIRED=(brands.json scoring.json)
status=0
checked=0

# Every executable bundle inside: the app itself and each embedded extension.
# An .appex deciding with an empty registry is exactly as dangerous as the app.
while IFS= read -r bundle; do
  name="$(basename "$bundle")"
  checked=$((checked + 1))
  for res in "${REQUIRED[@]}"; do
    if ! find "$bundle" -maxdepth 3 -name "$res" -print -quit | grep -q .; then
      echo "✘ $name : $res absent" >&2
      status=1
    fi
  done
done < <(find "$TARGET" \( -name "*.app" -o -name "*.appex" \) -print)

if [[ $checked -eq 0 ]]; then
  echo "✘ aucun bundle trouvé dans $TARGET" >&2
  exit 1
fi

if [[ $status -eq 0 ]]; then
  echo "OK : $checked bundle(s), registre et calibration présents dans chacun"
fi
exit $status
