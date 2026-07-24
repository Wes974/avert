// Perceptual hashing of logos (dHash), pure and DOM-free so the matching rules
// are unit-testable.
//
// Why this exists next to `l2.borrowed-brand-assets`: that signal only catches a
// logo *hotlinked* from the real brand's domain. The common phishing kit does the
// opposite — it copies the logo file into its own site, where no URL heuristic
// can see anything. A perceptual hash compares the pixels instead of the address,
// so a self-hosted copy of a bank's logo on an unrelated domain becomes visible.
//
// dHash (difference hash) rather than aHash/pHash: it is robust to rescaling and
// recompression (which every kit does) while staying trivial to compute and
// dependency-free, and it needs no DCT. 9×8 grayscale samples → 64 bits.

export const HASH_WIDTH = 9;
export const HASH_HEIGHT = 8;
export const HASH_SAMPLES = HASH_WIDTH * HASH_HEIGHT;

/**
 * Maximum Hamming distance still considered the same logo.
 *
 * Measured, not guessed (see `Tests/pages/logo-hash/`): on the same mark put
 * through the transforms a phishing kit actually applies — rescaled 200 %, 50 %,
 * 25 %, re-encoded as JPEG at quality 80 and 45, downscaled *and* re-encoded —
 * the distance ranged 4–9 bits. Between genuinely different marks it was 21–27.
 * 12 sits in that gap with margin on both sides.
 */
export const MATCH_THRESHOLD = 12;

/**
 * A hash carries no usable information when almost every comparison came out the
 * same way — a plain white banner, a flat colour block. Such images all collapse
 * to near-`0000…`, so matching on them would pair unrelated pictures at distance
 * 0. Both queries and references are held to this bar.
 */
export const MIN_INFORMATION_BITS = 10;

/**
 * dHash of a grayscale sample grid, row-major, `HASH_WIDTH × HASH_HEIGHT`
 * values in 0–255. Each row contributes 8 bits: is this pixel brighter than the
 * one to its right?
 *
 * Returns 16 lowercase hex chars, or null if the grid is the wrong size (a
 * caller that failed to sample must not silently produce a hash that matches
 * nothing in particular).
 */
export function dhash(gray: readonly number[]): string | null {
  if (gray.length !== HASH_SAMPLES) return null;

  let hex = "";
  for (let y = 0; y < HASH_HEIGHT; y++) {
    let rowBits = 0;
    for (let x = 0; x < HASH_WIDTH - 1; x++) {
      const left = gray[y * HASH_WIDTH + x] ?? 0;
      const right = gray[y * HASH_WIDTH + x + 1] ?? 0;
      rowBits = (rowBits << 1) | (left > right ? 1 : 0);
    }
    hex += rowBits.toString(16).padStart(2, "0");
  }
  return hex;
}

const BITS_SET = Array.from({ length: 256 }, (_, byte) => {
  let n = byte;
  let count = 0;
  while (n) {
    count += n & 1;
    n >>= 1;
  }
  return count;
});

/**
 * Hamming distance between two 16-hex-char hashes, or null if either is
 * malformed — an unparsable reference hash must not read as distance 0.
 */
export function hamming(a: string, b: string): number | null {
  if (a.length !== 16 || b.length !== 16) return null;
  let distance = 0;
  for (let i = 0; i < 16; i += 2) {
    const byteA = Number.parseInt(a.slice(i, i + 2), 16);
    const byteB = Number.parseInt(b.slice(i, i + 2), 16);
    if (Number.isNaN(byteA) || Number.isNaN(byteB)) return null;
    distance += BITS_SET[byteA ^ byteB] ?? 0;
  }
  return distance;
}

/** Set bits in a hash, or null if it is malformed. */
function popcount(hash: string): number | null {
  if (hash.length !== 16) return null;
  let bits = 0;
  for (let i = 0; i < 16; i += 2) {
    const byte = Number.parseInt(hash.slice(i, i + 2), 16);
    if (Number.isNaN(byte)) return null;
    bits += BITS_SET[byte] ?? 0;
  }
  return bits;
}

/** See `MIN_INFORMATION_BITS`. Symmetric: all-ones is as uninformative as all-zeros. */
export function isDiscriminative(hash: string): boolean {
  const bits = popcount(hash);
  if (bits === null) return false;
  return bits >= MIN_INFORMATION_BITS && bits <= 64 - MIN_INFORMATION_BITS;
}

/** Grayscale luminance from RGBA bytes (Rec. 601 — matches `sips` output). */
export function luminance(r: number, g: number, b: number): number {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/**
 * Area-average an RGBA buffer down to the `HASH_WIDTH × HASH_HEIGHT` grayscale
 * grid. Fully transparent pixels count as white: logos ship as transparent PNGs,
 * and reading them as black would hash the alpha silhouette rather than the mark.
 *
 * The reduction lives here, in shared code, on purpose. Letting the rasteriser do
 * it does not work: measured on iOS 26, `drawImage` into a 9×8 canvas
 * **point-samples** (the grid came back as the source's exact colours, no
 * averaging), so the hash depended on which source pixels happened to land on the
 * grid — it changed completely when the same logo was rescaled, which is the one
 * thing a perceptual hash must survive. `sips` on the Mac area-averages instead,
 * so the two sides disagreed by 17 of 64 bits on identical input.
 *
 * With the averaging done here, both sides only have to agree on decoding pixels
 * at their natural size, which is exact.
 */
export function grayFromRGBA(
  rgba: ArrayLike<number>,
  srcWidth = HASH_WIDTH,
  srcHeight = HASH_HEIGHT,
): number[] | null {
  if (srcWidth < HASH_WIDTH || srcHeight < HASH_HEIGHT) return null;
  if (rgba.length !== srcWidth * srcHeight * 4) return null;

  const gray: number[] = [];
  for (let ty = 0; ty < HASH_HEIGHT; ty++) {
    // Integer bucket bounds: uneven by up to one pixel, but identical on both
    // sides, which is what matters. Fractional weighting would buy accuracy the
    // threshold already absorbs.
    const y0 = Math.floor((ty * srcHeight) / HASH_HEIGHT);
    const y1 = Math.max(y0 + 1, Math.floor(((ty + 1) * srcHeight) / HASH_HEIGHT));
    for (let tx = 0; tx < HASH_WIDTH; tx++) {
      const x0 = Math.floor((tx * srcWidth) / HASH_WIDTH);
      const x1 = Math.max(x0 + 1, Math.floor(((tx + 1) * srcWidth) / HASH_WIDTH));

      let sum = 0;
      let count = 0;
      for (let y = y0; y < y1; y++) {
        for (let x = x0; x < x1; x++) {
          const i = (y * srcWidth + x) * 4;
          const alpha = (rgba[i + 3] ?? 255) / 255;
          const value = luminance(rgba[i] ?? 0, rgba[i + 1] ?? 0, rgba[i + 2] ?? 0);
          sum += value * alpha + 255 * (1 - alpha);
          count++;
        }
      }
      gray.push(count > 0 ? sum / count : 255);
    }
  }
  return gray;
}

export interface LogoOwner {
  brand: string;
  logoHashes: readonly string[];
}

/**
 * The brand whose reference logo this hash matches, or null.
 *
 * Closest match wins, so overlapping references can't make the result depend on
 * registry order. An empty reference table simply never matches — the signal is
 * inert until hashes are generated (`scripts/hash-logos.ts`), which is the
 * honest default: better silent than pretending to check.
 */
export function matchLogo(
  hash: string,
  owners: readonly LogoOwner[],
): { brand: string; distance: number } | null {
  if (!isDiscriminative(hash)) return null;

  let best: { brand: string; distance: number } | null = null;
  for (const owner of owners) {
    for (const reference of owner.logoHashes) {
      if (!isDiscriminative(reference)) continue;
      const distance = hamming(hash, reference);
      if (distance === null || distance > MATCH_THRESHOLD) continue;
      if (!best || distance < best.distance) best = { brand: owner.brand, distance };
    }
  }
  return best;
}
