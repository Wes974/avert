import type { CapturePoint } from "./types";

// L0 — capture-point trigger (PLAN.md §3). M0 ships the password detector to
// prove the pipeline; the remaining detectors (cc-*, OTP, seed phrase, ID
// upload) land in M1.

function isVisible(el: HTMLElement): boolean {
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  if (parseFloat(style.opacity) === 0) return false;
  const rect = el.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

function crossOriginActionHost(el: HTMLElement): string | null {
  const form = el.closest("form");
  if (!form) return null;
  const action = form.getAttribute("action");
  if (!action) return null;
  try {
    const actionUrl = new URL(action, window.location.href);
    return actionUrl.host !== window.location.host ? actionUrl.host : null;
  } catch {
    return null;
  }
}

export function detectCapturePoints(root: Document): CapturePoint[] {
  const points: CapturePoint[] = [];
  for (const input of root.querySelectorAll<HTMLInputElement>(
    'input[type="password"]',
  )) {
    points.push({
      kind: "password",
      visible: isVisible(input),
      inIframe: window.self !== window.top,
      crossOriginActionHost: crossOriginActionHost(input),
    });
  }
  return points;
}
