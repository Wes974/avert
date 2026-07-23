import type { CapturePoint, CapturePointKind } from "./types";

// L0 — capture-point trigger (PLAN.md §3). This is the gate that keeps the
// whole pipeline silent on ~95% of pages: no capture point, no analysis.

const PAYMENT_ATTR = /card.?n(um|o)|cardnumber|cvv|cvc|cryptogramme|num.?carte/i;
const OTP_ATTR = /\botp\b|one.?time|2fa|mfa|totp|verification.?code|code.?secur/i;
const SEED_ATTR = /seed|mnemonic|recovery.?phrase|secret.?phrase|phrase.?secr/i;
const ID_DOC_ATTR = /passport|passeport|identity|id.?card|cni|kyc|driver|permis/i;

function attrBlob(el: Element): string {
  return [
    el.getAttribute("name"),
    el.getAttribute("id"),
    el.getAttribute("placeholder"),
    el.getAttribute("aria-label"),
    el.getAttribute("autocomplete"),
  ]
    .filter(Boolean)
    .join(" ");
}

export function classifyInput(el: Element): CapturePointKind | null {
  const tag = el.tagName.toLowerCase();
  const type = (el.getAttribute("type") ?? "text").toLowerCase();
  const autocomplete = (el.getAttribute("autocomplete") ?? "").toLowerCase();
  const blob = attrBlob(el);

  if (tag === "input" && type === "password") return "password";
  if (autocomplete.startsWith("cc-")) return "payment-card";
  if (tag === "input" && PAYMENT_ATTR.test(blob)) return "payment-card";
  if (autocomplete === "one-time-code") return "otp";
  if (tag === "input" && OTP_ATTR.test(blob)) {
    const maxLen = parseInt(el.getAttribute("maxlength") ?? "99", 10);
    const numeric = (el.getAttribute("inputmode") ?? "") === "numeric";
    if (numeric || maxLen <= 8) return "otp";
  }
  if ((tag === "textarea" || tag === "input") && SEED_ATTR.test(blob)) return "seed-phrase";
  if (tag === "input" && type === "file" && ID_DOC_ATTR.test(blob)) return "id-document-upload";
  return null;
}

function isVisible(el: HTMLElement): boolean {
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  if (parseFloat(style.opacity) === 0) return false;
  const rect = el.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0;
}

function crossOriginActionHost(el: Element): string | null {
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
  for (const el of root.querySelectorAll("input, textarea")) {
    const kind = classifyInput(el);
    if (!kind) continue;
    points.push({
      kind,
      visible: el instanceof HTMLElement ? isVisible(el) : true,
      inIframe: window.self !== window.top,
      crossOriginActionHost: crossOriginActionHost(el),
    });
  }
  return points;
}
