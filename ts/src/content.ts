import { detectCapturePoints } from "./l0";
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
    capturePoints,
  };

  const response = await browser.runtime.sendMessage({
    type: "dossier",
    dossier,
  });

  if ("type" in response && response.type === "verdict") {
    // M0 round-trip proof: ack back to native, and leave a DOM marker that
    // UI-automation tests can assert on. M2 replaces this with the banner.
    document.documentElement.dataset["impostor"] = response.verdict.action;
    await browser.runtime.sendMessage({
      type: "ack",
      echoHost: response.verdict.echoHost ?? "",
    });
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => void run());
} else {
  void run();
}
