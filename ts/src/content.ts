import { detectCapturePoints } from "./l0";
import { analyzeUrl } from "./l1";
import { analyzePage } from "./l2";
import { BRANDS } from "./generated/brands";
import { renderVerdict } from "./banner";
import type { PageDossier } from "./types";

// Content script. L0 gate: no capture point → do strictly nothing (silence by
// default, PLAN.md §1). Otherwise build the page dossier and hand it to the
// background, which relays it to the native engine.

// Identity cues for L3 — deliberately NOT the page's prose.
//
// Two reasons converge on the same choice. (1) We only need what brand the page
// claims to be; the manipulative copy ("confirm your details for security…")
// is noise for that. (2) FoundationModels' guardrail rejects that lure copy as
// unsafe even in permissive mode (validated on device 2026-07-24), so feeding
// it guarantees a guardrailViolation. So we gather only strong brand signals:
// title, logo alt text, og:site_name / application-name, and short headings —
// never paragraphs. `textContent`, not `innerText`, so it's render-independent.
function identityCues(): string {
  const parts: string[] = [];
  const push = (s: string | null | undefined) => {
    const t = (s ?? "").trim();
    if (t && t.length <= 80) parts.push(t);
  };

  // Cleanest, lowest-risk brand cues first: they rarely carry lure wording.
  push(document.querySelector('meta[property="og:site_name"]')?.getAttribute("content"));
  push(document.querySelector('meta[name="application-name"]')?.getAttribute("content"));
  for (const img of document.querySelectorAll<HTMLImageElement>("img[alt]")) {
    const alt = img.getAttribute("alt") ?? "";
    if (/logo|brand/i.test(img.getAttribute("class") ?? "") || /logo/i.test(alt)) push(alt);
  }

  // Headings only as a fallback: a phishing heading like "Votre compte est
  // suspendu !" is exactly the lure wording that trips the model's guardrail,
  // so we avoid feeding it whenever a clean cue already exists.
  if (parts.length === 0) {
    let headings = 0;
    for (const h of document.querySelectorAll("h1, h2, legend")) {
      push(h.textContent);
      if (++headings >= 2) break;
    }
  }
  return [...new Set(parts)].join(" · ").slice(0, 400);
}

async function run(): Promise<void> {
  const t0 = performance.now();
  const capturePoints = detectCapturePoints(document);
  if (capturePoints.length === 0) return; // L0 gate — the common, ~0-cost path.

  const dossier: PageDossier = {
    version: 1,
    // Hostname only — never the full URL. The path/query of a sensitive page
    // often carries secrets (?token=…, magic links) and the native side never
    // uses anything but the host. L1 still parses the full href locally below.
    host: window.location.hostname,
    title: document.title.slice(0, 200),
    textExcerpt: identityCues(),
    capturePoints,
    l1Signals: analyzeUrl(window.location.href, BRANDS),
    l2Signals: analyzePage(document, window.location.hostname, capturePoints, BRANDS),
  };
  const jsMs = performance.now() - t0;

  const response = await browser.runtime.sendMessage({
    type: "dossier",
    dossier,
  });

  // Cold-start can resolve a nullish response; guard before touching it.
  if (
    response &&
    typeof response === "object" &&
    "type" in response &&
    response.type === "verdict"
  ) {
    // Debug builds carry a diagnostic string; prepend the JS-side latency
    // (L0+L1+L2 dossier build) so both halves of the timing are visible.
    if (response.verdict.debug) {
      response.verdict.debug = `js=${jsMs.toFixed(1)}ms · ${response.verdict.debug}`;
      // Detection oracle for UI-automation — DEBUG only. In release we never
      // mark the DOM, so a hostile page can't read whether it was flagged.
      document.documentElement.dataset["impostor"] = response.verdict.action;
    }
    renderVerdict(response.verdict);
    await browser.runtime.sendMessage({
      type: "ack",
      echoHost: response.verdict.echoHost ?? "",
    });
  }
}

function runReporting(): void {
  run().catch((err: unknown) => {
    void browser.runtime.sendMessage({
      type: "jsError",
      detail: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
    });
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", runReporting);
} else {
  runReporting();
}
