import { describe, expect, test } from "bun:test";
import {
  HASH_HEIGHT,
  HASH_SAMPLES,
  HASH_WIDTH,
  MATCH_THRESHOLD,
  dhash,
  grayFromRGBA,
  hamming,
  isDiscriminative,
  matchLogo,
} from "../src/dhash";

/** Grid built from a per-pixel function, row-major. */
function grid(f: (x: number, y: number) => number): number[] {
  const out: number[] = [];
  for (let y = 0; y < HASH_HEIGHT; y++) {
    for (let x = 0; x < HASH_WIDTH; x++) out.push(f(x, y));
  }
  return out;
}

describe("dhash", () => {
  test("a uniform image hashes to all zeros (no pixel is brighter than the next)", () => {
    expect(dhash(grid(() => 128))).toBe("0000000000000000");
  });

  test("a left-to-right dark→light ramp: every comparison is false", () => {
    expect(dhash(grid((x) => x * 25))).toBe("0000000000000000");
  });

  test("a light→dark ramp: every comparison is true", () => {
    expect(dhash(grid((x) => 255 - x * 25))).toBe("ffffffffffffffff");
  });

  test("rejects a grid of the wrong size rather than hashing garbage", () => {
    expect(dhash([1, 2, 3])).toBeNull();
    expect(dhash(new Array(HASH_SAMPLES - 1).fill(0))).toBeNull();
  });

  test("a uniform brightness shift leaves the hash unchanged", () => {
    // The property that makes dHash useful: it encodes gradients, not levels, so
    // a recompressed or rebrightened copy still matches.
    const dark = dhash(grid((x, y) => (x + y) % 2 === 0 ? 40 : 10));
    const bright = dhash(grid((x, y) => (x + y) % 2 === 0 ? 240 : 210));
    expect(dark).toBe(bright);
  });
});

describe("hamming", () => {
  test("identical hashes are at distance 0", () => {
    expect(hamming("0f0f0f0f0f0f0f0f", "0f0f0f0f0f0f0f0f")).toBe(0);
  });

  test("counts differing bits, not bytes", () => {
    expect(hamming("0000000000000000", "0000000000000001")).toBe(1);
    expect(hamming("0000000000000000", "00000000000000ff")).toBe(8);
    expect(hamming("0000000000000000", "ffffffffffffffff")).toBe(64);
  });

  test("a malformed hash gives null, never 0", () => {
    // Guards against a typo'd reference in brands.json reading as a perfect match.
    expect(hamming("abc", "0000000000000000")).toBeNull();
    expect(hamming("zzzzzzzzzzzzzzzz", "0000000000000000")).toBeNull();
  });
});

describe("grayFromRGBA", () => {
  test("a fully transparent pixel reads as white, not black", () => {
    // Logos ship as transparent PNGs; reading alpha as black would hash the
    // silhouette instead of the mark.
    const rgba = new Array(HASH_SAMPLES * 4).fill(0); // black, alpha 0
    const gray = grayFromRGBA(rgba);
    expect(gray?.every((v) => v === 255)).toBe(true);
  });

  test("green weighs more than blue (Rec. 601)", () => {
    const one = (r: number, g: number, b: number) =>
      grayFromRGBA(new Array(HASH_SAMPLES).fill([r, g, b, 255]).flat())?.[0] ?? 0;
    expect(one(0, 255, 0)).toBeGreaterThan(one(0, 0, 255));
  });

  test("rejects a buffer of the wrong length", () => {
    expect(grayFromRGBA([0, 0, 0, 255])).toBeNull();
  });
});

describe("matchLogo", () => {
  const paypal = { brand: "PayPal", logoHashes: ["f0f0f0f0f0f0f0f0"] };

  test("an exact hash matches its brand", () => {
    expect(matchLogo("f0f0f0f0f0f0f0f0", [paypal])?.brand).toBe("PayPal");
  });

  test("a near miss within the threshold still matches", () => {
    // One bit off — a rescaled copy of the same logo.
    expect(matchLogo("f0f0f0f0f0f0f0f1", [paypal])?.distance).toBe(1);
  });

  test("beyond the threshold it does not match", () => {
    expect(matchLogo("0f0f0f0f0f0f0f0f", [paypal])).toBeNull();
  });

  test("the closest reference wins, so registry order can't decide", () => {
    const near = { brand: "Proche", logoHashes: ["f0f0f0f0f0f0f0f1"] };
    const far = { brand: "Loin", logoHashes: ["f0f0f0f0f0f0f0f7"] };
    expect(matchLogo("f0f0f0f0f0f0f0f0", [far, near])?.brand).toBe("Proche");
    expect(matchLogo("f0f0f0f0f0f0f0f0", [near, far])?.brand).toBe("Proche");
  });

  test("an empty reference table never matches", () => {
    // Current state of the registry: the signal ships inert rather than
    // pretending to check.
    expect(matchLogo("f0f0f0f0f0f0f0f0", [])).toBeNull();
    expect(matchLogo("f0f0f0f0f0f0f0f0", [{ brand: "X", logoHashes: [] }])).toBeNull();
  });

  test("a near-uniform image never matches anything", () => {
    // A blank banner hashes to ~0 and would otherwise pair with any other flat
    // image at distance 0 — the worst false positive available.
    const blank = { brand: "Vide", logoHashes: ["0000000000000000"] };
    expect(matchLogo("0000000000000000", [blank])).toBeNull();
    expect(matchLogo("0000000000000001", [paypal])).toBeNull();
  });
});

describe("isDiscriminative", () => {
  test("rejects flat images at both extremes and accepts real marks", () => {
    expect(isDiscriminative("0000000000000000")).toBe(false);
    expect(isDiscriminative("ffffffffffffffff")).toBe(false);
    expect(isDiscriminative("f0f0f0f0f0f0f0f0")).toBe(true);
    expect(isDiscriminative("nope")).toBe(false);
  });
});

/**
 * Measured on real files (`Tests/pages/logo-hash/`), not invented: these are the
 * hashes the generator produced *and* the ones Safari computed on iOS 26 —
 * bit-for-bit identical, which is what makes the reference table portable.
 *
 * Keeping them here as data locks the threshold against the measurement, on any
 * platform, without needing an image decoder in CI.
 */
describe("calibration mesurée", () => {
  const MARK_A = "c0cc84c4c830f0d0";           // 240×200 PNG
  const MARK_A_DEGRADED = "cbcce4c4c8f0f0ec";  // même marque : 96 px + JPEG q60
  const MARK_B = "0000bbabc8000000";           // autre marque (mot-symbole)
  const MARK_C = "00cccc8c8ccccc00";           // autre marque (PNG transparent)

  test("une copie redimensionnée et recompressée reste sous le seuil", () => {
    const d = hamming(MARK_A, MARK_A_DEGRADED);
    expect(d).not.toBeNull();
    expect(d!).toBeLessThanOrEqual(MATCH_THRESHOLD);
  });

  test("des marques différentes restent bien au-dessus du seuil", () => {
    for (const [x, y] of [[MARK_A, MARK_B], [MARK_A, MARK_C], [MARK_B, MARK_C]]) {
      expect(hamming(x!, y!)!).toBeGreaterThan(MATCH_THRESHOLD + 6);
    }
  });

  test("le seuil reste dans l'intervalle mesuré (9 < seuil < 21)", () => {
    // Si quelqu'un le desserre au-delà, des marques distinctes commencent à se
    // confondre ; en dessous, une simple recompression n'est plus reconnue.
    expect(MATCH_THRESHOLD).toBeGreaterThan(9);
    expect(MATCH_THRESHOLD).toBeLessThan(21);
    expect(HASH_WIDTH * HASH_HEIGHT).toBe(HASH_SAMPLES);
  });

  test("toutes les empreintes de référence sont discriminantes", () => {
    for (const h of [MARK_A, MARK_A_DEGRADED, MARK_B, MARK_C]) {
      expect(isDiscriminative(h)).toBe(true);
    }
  });
});
