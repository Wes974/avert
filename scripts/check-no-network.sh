#!/bin/bash
# Network guard — the load-bearing privacy claim of this app is "no page data
# leaves the device". That claim is one careless `fetch()` away from being false,
# and nothing else in the toolchain would notice. So the bundles are grepped for
# every way a browser can talk to the network.
#
# Run against the shipped artifacts, not the sources: what matters is what ends
# up in Extension/Resources/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLES=("$ROOT/Extension/Resources/content.js" "$ROOT/Extension/Resources/background.js")

# Identifiers that can reach the network from a content or background script.
# `import(` is here because a dynamic import can fetch a remote module.
FORBIDDEN='fetch\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|navigator\.connection|import\(|new Worker|importScripts'

status=0
for bundle in "${BUNDLES[@]}"; do
  if [[ ! -f "$bundle" ]]; then
    echo "✘ absent : $bundle (lancer ./scripts/build-js.sh)" >&2
    status=1
    continue
  fi

  if hits=$(grep -oE "$FORBIDDEN" "$bundle" | sort -u) && [[ -n "$hits" ]]; then
    echo "✘ $(basename "$bundle") contient des API réseau :" >&2
    echo "$hits" | sed 's/^/    /' >&2
    status=1
  fi

  # Any absolute URL in the bundle is suspect too: a remote asset, a beacon
  # endpoint, a "documentation" link that becomes a request. The registry holds
  # bare hostnames, never URLs, so there is no legitimate case for one here.
  if urls=$(grep -oE 'https?://[a-zA-Z0-9.-]+' "$bundle" | sort -u) && [[ -n "$urls" ]]; then
    echo "✘ $(basename "$bundle") contient des URL absolues :" >&2
    echo "$urls" | sed 's/^/    /' >&2
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "OK : aucun appel réseau possible depuis les bundles"
fi
exit $status
