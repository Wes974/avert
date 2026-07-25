#!/bin/bash
# Typecheck + bundle the TS sources into Extension/Resources/.
# The repo lives in iCloud Drive: node_modules must never exist here, and bun
# needs a redirected TMPDIR. So we copy ts/ to a scratch dir, work there, and
# only bring the bundled .js files back.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${TMPDIR:-/tmp}/impostor-js"

# bun refuses to run if its tempdir/cache aren't writable (sandbox + iCloud):
# pin both inside the scratch dir, before the first bun invocation.
export TMPDIR="$SCRATCH/tmp"
export BUN_INSTALL_CACHE_DIR="$SCRATCH/.buncache"
mkdir -p "$TMPDIR" "$BUN_INSTALL_CACHE_DIR"

# The registry is data, and bad data here fails silently at runtime (a brand made
# unverifiable, or a host wrongly attributed). Check it before generating from it.
(cd "$ROOT" && bun run scripts/lint-registry.ts)

# Single source of truth for the brand registry: registry/brands.json.
# The TS side consumes a generated (and committed) module.
mkdir -p "$ROOT/ts/src/generated"
{
  echo "// GENERATED from registry/brands.json by scripts/build-js.sh — do not edit."
  echo 'import type { BrandEntry } from "../l1";'
  printf 'export const BRANDS: BrandEntry[] = '
  cat "$ROOT/registry/brands.json"
  echo ';'
} > "$ROOT/ts/src/generated/brands.ts"

mkdir -p "$SCRATCH"
rsync -a --delete --exclude node_modules "$ROOT/ts/" "$SCRATCH/"

# The L1 corpus lives outside ts/ because the Swift tests read the same file
# (Tests/corpus/l1.json is the anti-drift contract between the two L1 engines).
# Mirror the repo-relative path the test imports, so it resolves in the scratch.
mkdir -p "$SCRATCH/../Tests/corpus"
rsync -a "$ROOT/Tests/corpus/" "$SCRATCH/../Tests/corpus/"

cd "$SCRATCH"
bun install --silent
bunx tsc --noEmit
bun test

for entry in content background; do
  # Minified: content.js is parsed on every page (all_urls); ~95% have no
  # capture point and stop at L0, so keep the bytes down.
  bun build "src/$entry.ts" --format=iife --target=browser --minify \
    --outfile="$ROOT/Extension/Resources/$entry.js"
done

"$ROOT/scripts/check-no-network.sh"

echo "OK: Extension/Resources/{content,background}.js"
