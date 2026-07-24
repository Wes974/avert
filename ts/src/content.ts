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

  push(document.querySelector('meta[property="og:site_name"]')?.getAttribute("content"));
  push(document.querySelector('meta[name="application-name"]')?.getAttribute("content"));

  for (const img of document.querySelectorAll<HTMLImageElement>("img[alt]")) {
    const alt = img.getAttribute("alt") ?? "";
    // Logo-ish alt text is the cleanest brand cue.
    if (/logo|brand/i.test(img.getAttribute("class") ?? "") || /logo/i.test(alt)) push(alt);
  }

  let headings = 0;
  for (const h of document.querySelectorAll("h1, h2, h3, legend")) {
    push(h.textContent);
    if (++headings >= 4) break;
  }
  // Dedup, cap length.
  return [...new Set(parts)].join(" · ").slice(0, 400);
}

async function run(): Promise<void> {
  const capturePoints = detectCapturePoints(document);
  if (capturePoints.length === 0) return;

  const dossier: PageDossier = {
    version: 1,
    url: window.location.href,
    host: window.location.host,
    title: document.title.slice(0, 200),
    textExcerpt: identityCues(),
    capturePoints,
    l1Signals: analyzeUrl(window.location.href, BRANDS),
    l2Signals: analyzePage(document, window.location.host, capturePoints, BRANDS),
  };

  const response = await browser.runtime.sendMessage({
    type: "dossier",
    dossier,
  });

  if ("type" in response && response.type === "verdict") {
    // DOM marker kept for UI-automation assertions.
    document.documentElement.dataset["impostor"] = response.verdict.action;
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
