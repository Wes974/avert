import type { BrandEntry } from "./l1";
import { registrableDomain } from "./l1";
import type { CapturePoint } from "./types";

// L2 — page structure & behaviour (PLAN.md §3). Runs only when L0 found a
// capture point, so cost stays bounded to sensitive pages.

export interface L2Signal {
  id:
    | "l2.cross-origin-form"
    | "l2.hidden-capture-field"
    | "l2.thirdparty-iframe"
    | "l2.anti-inspection"
    | "l2.borrowed-brand-assets"
    // Emitted by frames.ts on the top frame, not by analyzePage.
    | "l2.capture-in-thirdparty-iframe"
    // Emitted by logo.ts (perceptual hash), not by analyzePage.
    | "l2.brand-logo-copy";
  detail?: string;
  brand?: string;
}

function brandCoversHost(brand: BrandEntry, host: string): boolean {
  const reg = registrableDomain(host);
  return (
    brand.domains.some((d) => reg === registrableDomain(d)) ||
    brand.auth_delegates.some((d) => reg === registrableDomain(d.replace(/^\*\./, "")))
  );
}

function brandOwning(host: string, brands: BrandEntry[]): BrandEntry | null {
  return brands.find((b) => brandCoversHost(b, host)) ?? null;
}

export function analyzePage(
  doc: Document,
  pageHost: string,
  capturePoints: CapturePoint[],
  brands: BrandEntry[],
): L2Signal[] {
  const signals: L2Signal[] = [];

  // Cross-origin form action / hidden capture fields come from L0's per-field
  // observations — L2 turns them into page-level signals.
  const pageBrand = brandOwning(pageHost, brands);
  const crossOrigin = capturePoints.find((p) => p.crossOriginActionHost);
  const actionHost = crossOrigin?.crossOriginActionHost;
  if (actionHost) {
    // A page posting credentials off-origin is a strong signal — UNLESS it
    // posts to its own brand's authentication delegate (SSO, FranceConnect,
    // bank auth providers). That is the whole point of auth_delegates and the
    // main false-positive remedy (PLAN §4).
    const legitDelegate = pageBrand != null && brandCoversHost(pageBrand, actionHost);
    if (!legitDelegate) {
      signals.push({ id: "l2.cross-origin-form", detail: actionHost });
    }
  }
  if (capturePoints.some((p) => !p.visible)) {
    // A page that hides its own credential fields is suspicious by
    // construction — the ruse becomes the tell.
    signals.push({ id: "l2.hidden-capture-field" });
  }

  // Third-party iframes big enough to host a form (cross-origin content is
  // opaque to us; presence next to capture points is the signal).
  for (const iframe of doc.querySelectorAll("iframe[src]")) {
    try {
      const src = new URL(iframe.getAttribute("src") ?? "", `https://${pageHost}`);
      if (src.host && src.host !== pageHost && !brandOwning(src.host, brands)) {
        const w = parseInt(iframe.getAttribute("width") ?? "0", 10);
        const h = parseInt(iframe.getAttribute("height") ?? "0", 10);
        const rect =
          iframe instanceof HTMLElement ? iframe.getBoundingClientRect() : { width: w, height: h };
        if ((rect.width || w) >= 200 && (rect.height || h) >= 100) {
          signals.push({ id: "l2.thirdparty-iframe", detail: src.host });
          break;
        }
      }
    } catch {
      // unparsable src: ignore
    }
  }

  // Anti-inspection heuristics: inline handlers blocking context menu /
  // selection / copy. (Listener-based blocking is invisible to us — this only
  // catches the lazy variant, which is the common one in phishing kits.)
  const body = doc.body;
  const antiInspection: string[] = [];
  if (doc.documentElement.getAttribute("oncontextmenu") || body?.getAttribute("oncontextmenu")) {
    antiInspection.push("contextmenu");
  }
  if (body?.getAttribute("onselectstart") || body?.getAttribute("oncopy")) {
    antiInspection.push("selection");
  }
  if (body && typeof window !== "undefined") {
    const style = window.getComputedStyle(body);
    if (style.userSelect === "none") antiInspection.push("user-select");
  }
  if (antiInspection.length > 0) {
    signals.push({ id: "l2.anti-inspection", detail: antiInspection.join(",") });
  }

  // Borrowed visual identity: favicon or logo images served from a registry
  // brand's domain while the page host is not that brand.
  const assetHosts = new Set<string>();
  for (const link of doc.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')) {
    const href = link.getAttribute("href");
    if (href) {
      try {
        assetHosts.add(new URL(href, `https://${pageHost}`).host);
      } catch {
        /* ignore */
      }
    }
  }
  let imgCount = 0;
  for (const img of doc.querySelectorAll("img[src]")) {
    if (imgCount++ >= 50) break;
    try {
      assetHosts.add(new URL(img.getAttribute("src") ?? "", `https://${pageHost}`).host);
    } catch {
      /* ignore */
    }
  }
  const pageOwner = brandOwning(pageHost, brands);
  for (const host of assetHosts) {
    if (host === pageHost) continue;
    const assetOwner = brandOwning(host, brands);
    if (assetOwner && assetOwner !== pageOwner) {
      signals.push({
        id: "l2.borrowed-brand-assets",
        detail: host,
        brand: assetOwner.brand,
      });
      break;
    }
  }

  return signals;
}
