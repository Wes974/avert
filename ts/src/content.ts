import { detectCapturePoints } from "./l0";
import { analyzeUrl } from "./l1";
import { analyzePage } from "./l2";
import { BRANDS } from "./generated/brands";
import { renderVerdict, clearVerdict } from "./banner";
import {
  frameSignals,
  pageSignature,
  synthesizeFramePoints,
  type FrameCapture,
} from "./frames";
import type { CapturePoint, PageDossier, VerdictAction } from "./types";

// Content script. L0 gate: no capture point → do strictly nothing (silence by
// default, PLAN.md §1). Otherwise build the page dossier and hand it to the
// background, which relays it to the native engine.
//
// Runs in every frame (manifest `all_frames`), with two very different roles:
//   • subframe — L0 only, reports its capture points to the top frame, no UI,
//     no native call. Cheap, and it never decides anything.
//   • top frame — owns the decision, the native call and the UI, and re-runs
//     when the page changes under it (SPA route changes mutate the DOM instead
//     of loading a document, so `DOMContentLoaded` alone misses them).

const IS_TOP = window.top === window;

/** Re-evaluations allowed per document. Bounds L3 cost on a mutating SPA. */
const MAX_EVALUATIONS = 4;
const RESCAN_DEBOUNCE_MS = 500;

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

// ---------------------------------------------------------------- top frame

/** Capture points reported by subframes, keyed by frame host (last wins). */
const frameReports = new Map<string, FrameCapture>();

let evaluations = 0;
let lastSignature = "";
let shownAction: VerdictAction = "silent";

/**
 * Reports from frames the document no longer contains are stale — an SPA that
 * tore down its payment iframe must not keep contributing a capture point.
 * Comparing `src` hostnames works cross-origin; frames without a resolvable
 * host (srcdoc, about:blank) are same-document by construction.
 */
function liveFrameReports(): FrameCapture[] {
  const hosts = new Set<string>();
  for (const frame of document.querySelectorAll<HTMLIFrameElement>("iframe[src]")) {
    try {
      hosts.add(new URL(frame.src, window.location.href).hostname);
    } catch {
      // Unparsable src — ignore rather than guess.
    }
  }
  for (const host of frameReports.keys()) {
    if (!hosts.has(host)) frameReports.delete(host);
  }
  return [...frameReports.values()];
}

async function evaluate(): Promise<void> {
  const own = detectCapturePoints(document);
  const reports = liveFrameReports();
  const framePoints = synthesizeFramePoints(reports);
  const capturePoints: CapturePoint[] = [...own, ...framePoints];

  // L0 gate — the common, ~0-cost path. If an alert was up for a state that no
  // longer exists (SPA navigated away from the login screen), take it down: a
  // warning left hanging over unrelated content is its own kind of lie.
  if (capturePoints.length === 0) {
    if (shownAction !== "silent") {
      clearVerdict();
      shownAction = "silent";
    }
    lastSignature = "";
    return;
  }

  const signature = pageSignature(
    window.location.hostname,
    window.location.pathname,
    capturePoints,
  );
  if (signature === lastSignature || evaluations >= MAX_EVALUATIONS) return;
  lastSignature = signature;
  evaluations += 1;

  const t0 = performance.now();
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
    l2Signals: [
      ...analyzePage(document, window.location.hostname, capturePoints, BRANDS),
      ...frameSignals(reports, window.location.hostname, BRANDS),
    ],
  };
  const jsMs = performance.now() - t0;

  const response = await browser.runtime.sendMessage({ type: "dossier", dossier });

  // Cold-start can resolve a nullish response; guard before touching it.
  if (
    !response ||
    typeof response !== "object" ||
    !("type" in response) ||
    response.type !== "verdict"
  ) {
    return;
  }

  // Debug builds carry a diagnostic string; prepend the JS-side latency
  // (L0+L1+L2 dossier build) so both halves of the timing are visible.
  if (response.verdict.debug) {
    response.verdict.debug = `js=${jsMs.toFixed(1)}ms · pass=${evaluations} · ${response.verdict.debug}`;
    // Detection oracle for UI-automation — DEBUG only. In release we never
    // mark the DOM, so a hostile page can't read whether it was flagged.
    document.documentElement.dataset["impostor"] = response.verdict.action;
  }

  // Replace rather than stack: a second pass may upgrade a banner to an
  // interstitial, and `renderVerdict` is a no-op while a host is still up.
  if (shownAction !== "silent" && response.verdict.action !== shownAction) {
    clearVerdict();
    shownAction = "silent";
  }
  if (response.verdict.action !== "silent") {
    renderVerdict(response.verdict);
    shownAction = response.verdict.action;
  }

  await browser.runtime.sendMessage({
    type: "ack",
    echoHost: response.verdict.echoHost ?? "",
  });
}

/**
 * Re-evaluate when the page changes under us. SPAs swap a login screen in
 * without a document load, and `pushState` can't be hooked from a content
 * script's isolated world — so the DOM itself is the signal, debounced, and
 * gated by `pageSignature` so an unchanged state costs nothing.
 */
function watchForChanges(): void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const observer = new MutationObserver(schedule);

  function schedule(): void {
    if (evaluations >= MAX_EVALUATIONS) {
      observer.disconnect();
      return;
    }
    if (timer !== undefined) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = undefined;
      runReporting();
    }, RESCAN_DEBOUNCE_MS);
  }

  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("popstate", schedule);
  window.addEventListener("hashchange", schedule);
}

function listenForFrameReports(): void {
  browser.runtime.onMessage.addListener((message) => {
    if (message.type !== "frameCapture") return;
    const previous = frameReports.get(message.frameHost);
    frameReports.set(message.frameHost, {
      frameHost: message.frameHost,
      kinds: message.kinds,
    });
    // Only pay for a pass when the report actually adds something.
    if (!previous || previous.kinds.join(",") !== message.kinds.join(",")) {
      runReporting();
    }
  });
}

// ---------------------------------------------------------------- subframe

/**
 * Subframes only report. They never call the engine and never draw: an alert
 * inside a 300×200 payment frame would be both unreadable and trivially
 * hidden by the embedding page.
 */
function reportToTopFrame(): void {
  let reported = "";
  let reports = 0;

  const send = () => {
    const kinds = [...new Set(detectCapturePoints(document).map((p) => p.kind))].sort();
    const digest = kinds.join(",");
    if (digest === reported) return;
    reported = digest;
    reports += 1;
    void browser.runtime.sendMessage({
      type: "frameCapture",
      frameHost: window.location.hostname,
      kinds,
    });
  };

  send();

  // Embedded payment/auth frames build their fields asynchronously, so a single
  // pass at load time misses most of them. Same debounce and cap as the top
  // frame, and the observer stops as soon as the budget is spent.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const observer = new MutationObserver(() => {
    if (reports >= MAX_EVALUATIONS) {
      observer.disconnect();
      return;
    }
    if (timer !== undefined) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = undefined;
      send();
    }, RESCAN_DEBOUNCE_MS);
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
}

// ---------------------------------------------------------------- bootstrap

function runReporting(): void {
  evaluate().catch((err: unknown) => {
    void browser.runtime.sendMessage({
      type: "jsError",
      detail: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
    });
  });
}

function start(): void {
  if (!IS_TOP) {
    reportToTopFrame();
    return;
  }
  listenForFrameReports();
  runReporting();
  watchForChanges();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", start);
} else {
  start();
}
