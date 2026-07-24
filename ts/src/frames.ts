import type { BrandEntry } from "./l1";
import { registrableDomain } from "./l1";
import type { CapturePoint, CapturePointKind } from "./types";
import type { L2Signal } from "./l2";

// Cross-frame coverage (PLAN.md §3, gap found in the 2026-07-24 review).
//
// A phishing kit can put the credential form in a cross-origin iframe: the top
// frame then has no capture point at all, L0 gates everything out, and Avert
// stays silent on exactly the page it exists for. So the content script now runs
// in every frame; subframes report their capture points to the top frame, which
// remains the only one deciding and the only one showing UI (it is the frame the
// user reads the address of, and the only one big enough to host an alert).
//
// The helpers here are pure so the merge rules are testable without a browser.

export interface FrameCapture {
  /** Hostname of the reporting subframe. */
  frameHost: string;
  kinds: CapturePointKind[];
}

/** Capture points contributed by subframes, flagged `inIframe`. */
export function synthesizeFramePoints(frames: FrameCapture[]): CapturePoint[] {
  const points: CapturePoint[] = [];
  for (const frame of frames) {
    for (const kind of new Set(frame.kinds)) {
      points.push({
        kind,
        visible: true,
        inIframe: true,
        // The form's action host is unknown from here — the subframe's own L2
        // pass owns that. Left null so no cross-origin-form weight is inferred.
        crossOriginActionHost: null,
      });
    }
  }
  return points;
}

function sameSite(a: string, b: string): boolean {
  return registrableDomain(a) === registrableDomain(b);
}

function brandOwns(brand: BrandEntry, host: string): boolean {
  const reg = registrableDomain(host);
  return (
    brand.domains.some((d) => reg === registrableDomain(d)) ||
    brand.auth_delegates.some((d) => reg === registrableDomain(d.replace(/^\*\./, "")))
  );
}

/**
 * Page-level signal for "the secret is typed into someone else's frame".
 *
 * Exemptions matter more than the signal itself: same-site frames are normal
 * (a bank's own SSO frame), and so is a frame belonging to the very brand that
 * owns the page — that is how legitimate delegated auth looks. Everything else
 * gets a deliberately modest weight: embedded payment fields (Stripe, Adyen…)
 * are legitimate and common, so this must never alert on its own.
 */
export function frameSignals(
  frames: FrameCapture[],
  pageHost: string,
  brands: BrandEntry[],
): L2Signal[] {
  const pageBrand = brands.find((b) => brandOwns(b, pageHost)) ?? null;
  const foreign = frames.filter(
    (f) =>
      f.kinds.length > 0 &&
      !sameSite(f.frameHost, pageHost) &&
      !(pageBrand && brandOwns(pageBrand, f.frameHost)),
  );
  if (foreign.length === 0) return [];
  return [
    {
      id: "l2.capture-in-thirdparty-iframe",
      detail: [...new Set(foreign.map((f) => f.frameHost))].sort().join(","),
    },
  ];
}

/**
 * Identity of the current evaluated state. Re-evaluating an unchanged state
 * would pay for L3 (~2.3 s on device) for nothing, and SPAs mutate the DOM
 * constantly — so the pipeline only re-runs when this string changes.
 */
export function pageSignature(
  host: string,
  path: string,
  points: CapturePoint[],
): string {
  const kinds = [...new Set(points.map((p) => `${p.kind}${p.inIframe ? "@iframe" : ""}`))];
  return [host, path, kinds.sort().join(",")].join("|");
}
