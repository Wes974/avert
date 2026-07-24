import type { BrandEntry } from "./l1";
import { registrableDomain } from "./l1";
import type { L2Signal } from "./l2";
import {
  HASH_HEIGHT,
  HASH_WIDTH,
  dhash,
  grayFromRGBA,
  matchLogo,
  type LogoOwner,
} from "./dhash";

// DOM glue for logo hashing. The rules live in `dhash.ts`; everything here is
// browser plumbing, kept thin because it cannot be unit-tested (happy-dom has no
// canvas rasteriser).

/** Images hashed per page. Bounds the cost on an image-heavy page. */
const MAX_CANDIDATES = 8;

/**
 * Images are rasterised at their natural size (a 1:1 blit) and reduced by
 * `grayFromRGBA`, never by the canvas: on iOS 26 `drawImage` point-samples when
 * asked to shrink hard, which made the hash flip on any rescaling. See the note
 * in `dhash.ts`.
 *
 * The cap is what keeps a 1:1 blit affordable — 640² × 4 bytes ≈ 1.6 MB per
 * image. Logos are far smaller; anything bigger is a photo, not a mark.
 */
const MAX_DIMENSION = 640;

/**
 * Only images the browser has *already* loaded and that are readable are
 * hashed:
 *
 *   • Cross-origin images taint the canvas, so `getImageData` throws. Re-fetching
 *     them with `crossOrigin` would be a network request — forbidden here, and it
 *     would also tell the page it is being inspected. A hotlinked brand logo is
 *     already covered by `l2.borrowed-brand-assets`, which reads the URL instead.
 *   • Same-origin (or `data:`) images are exactly the interesting case: a kit that
 *     copied the logo into its own site, which no URL heuristic can see.
 */
function isReadable(img: HTMLImageElement, pageHost: string): boolean {
  const raw = img.getAttribute("src") ?? "";
  if (raw.startsWith("data:")) return true;
  try {
    return new URL(raw, window.location.href).hostname === pageHost;
  } catch {
    return false;
  }
}

/** Logo-ish images first, then any small loaded image (logos are small). */
function candidates(doc: Document, pageHost: string): HTMLImageElement[] {
  const all = [...doc.querySelectorAll<HTMLImageElement>("img[src]")].filter(
    (img) => img.complete && img.naturalWidth > 0 && isReadable(img, pageHost),
  );
  const looksLikeLogo = (img: HTMLImageElement) =>
    /logo|brand/i.test(`${img.getAttribute("class") ?? ""} ${img.getAttribute("alt") ?? ""} ${img.getAttribute("id") ?? ""}`);
  const hashable = all.filter(
    (img) =>
      img.naturalWidth >= HASH_WIDTH &&
      img.naturalHeight >= HASH_HEIGHT &&
      img.naturalWidth <= MAX_DIMENSION &&
      img.naturalHeight <= MAX_DIMENSION,
  );
  const named = hashable.filter(looksLikeLogo);
  const rest = hashable.filter((img) => !looksLikeLogo(img) && img.naturalWidth >= 16);
  return [...named, ...rest].slice(0, MAX_CANDIDATES);
}

/** dHash of one loaded image, or null if it can't be rasterised or read. */
function hashImage(img: HTMLImageElement): string | null {
  try {
    const w = img.naturalWidth;
    const h = img.naturalHeight;
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (!ctx) return null;
    // 1:1, so the canvas never resamples — the reduction is ours (see dhash.ts).
    // No white fill needed: transparency is composited by grayFromRGBA.
    ctx.drawImage(img, 0, 0);
    const gray = grayFromRGBA(ctx.getImageData(0, 0, w, h).data, w, h);
    return gray ? dhash(gray) : null;
  } catch {
    // SecurityError on a tainted canvas, or an image the decoder rejected.
    return null;
  }
}

function owners(brands: BrandEntry[]): LogoOwner[] {
  return brands
    .filter((b) => (b.logo_hashes?.length ?? 0) > 0)
    .map((b) => ({ brand: b.brand, logoHashes: b.logo_hashes ?? [] }));
}

function brandCoversHost(brand: BrandEntry, host: string): boolean {
  const reg = registrableDomain(host);
  return (
    brand.domains.some((d) => reg === registrableDomain(d)) ||
    brand.auth_delegates.some((d) => reg === registrableDomain(d.replace(/^\*\./, "")))
  );
}

/**
 * `l2.brand-logo-copy` — a registry brand's logo is displayed, pixel-wise, on a
 * host that brand does not own. This is an identity claim contradicted by the
 * domain, so `ScoreEngine` treats it as an identity signal.
 *
 * Returns nothing when the reference table is empty, which is the current state
 * of the registry: the plumbing ships inert rather than pretending to check.
 */
export function logoSignals(
  doc: Document,
  pageHost: string,
  brands: BrandEntry[],
): L2Signal[] {
  const table = owners(brands);
  if (table.length === 0) return [];

  for (const img of candidates(doc, pageHost)) {
    const hash = hashImage(img);
    if (!hash) continue;
    const match = matchLogo(hash, table);
    if (!match) continue;

    const owner = brands.find((b) => b.brand === match.brand);
    // The brand's own site legitimately shows its own logo.
    if (owner && brandCoversHost(owner, pageHost)) continue;

    return [
      {
        id: "l2.brand-logo-copy",
        detail: `${hash}@${match.distance}`,
        brand: match.brand,
      },
    ];
  }
  return [];
}
