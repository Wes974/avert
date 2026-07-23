import { detectCapturePoints } from "./l0";
import { analyzeUrl } from "./l1";
import { analyzePage } from "./l2";
import { BRANDS } from "./generated/brands";
import { renderVerdict } from "./banner";
import type { PageDossier } from "./types";

// Content script. L0 gate: no capture point → do strictly nothing (silence by
// default, PLAN.md §1). Otherwise build the page dossier and hand it to the
// background, which relays it to the native engine.

async function run(): Promise<void> {
  const capturePoints = detectCapturePoints(document);
  if (capturePoints.length === 0) return;

  const dossier: PageDossier = {
    version: 1,
    url: window.location.href,
    host: window.location.host,
    title: document.title.slice(0, 200),
    textExcerpt: (document.body?.innerText ?? "").replace(/\s+/g, " ").slice(0, 1500),
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
