// Generate logo dHash references for registry/brands.json.
//
//   bun run scripts/hash-logos.ts <brand> <image…>        # print hashes
//   bun run scripts/hash-logos.ts --write <brand> <image…> # merge into registry
//
// `<brand>` must match a `brand` or alias already in the registry. Pass several
// renditions of the same logo (light/dark, wordmark/monogram, favicon) — each
// becomes its own reference, since a 64-bit dHash only describes one image.
//
// This must produce exactly what the browser produces in `ts/src/logo.ts`, or the
// references match nothing. So neither side resamples: `sips` only *decodes* the
// file to a BMP at its natural size, and the reduction to 9×8 is done by the
// shared `grayFromRGBA`.
//
// Letting the two rasterisers each do the downscale was the first attempt and it
// failed outright — Safari point-samples a hard shrink while sips area-averages,
// 17 of 64 bits apart on the same file. Measured with Tests/pages/logo-hash/,
// which is the fixture to re-run if this ever drifts again.

import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { HASH_HEIGHT, HASH_WIDTH, dhash, grayFromRGBA } from "../ts/src/dhash";

const REGISTRY = "registry/brands.json";
// sips needs a writable temp dir; the default under /var/folders is denied in the
// sandbox this repo is developed in.
const SCRATCH = join(process.env["TMPDIR"] ?? "/tmp", "avert-logo-hash");

interface Entry {
  brand: string;
  aliases: string[];
  logo_hashes?: string[];
  [key: string]: unknown;
}

function fold(s: string): string {
  return s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim();
}

/** Natural-size RGBA pixels from an image file, via sips → BMP. */
function pixels(path: string): { rgba: Uint8Array; width: number; height: number } {
  mkdirSync(SCRATCH, { recursive: true });
  const bmp = join(SCRATCH, `${basename(path)}.bmp`);
  const result = Bun.spawnSync({
    // Decode only — no -z. Resizing here is what broke the first version.
    cmd: ["sips", "-s", "format", "bmp", path, "--out", bmp],
    env: { ...process.env, TMPDIR: SCRATCH },
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0 || !existsSync(bmp)) {
    throw new Error(`sips a échoué sur ${path}: ${result.stderr.toString().trim()}`);
  }

  const data = readFileSync(bmp);
  unlinkSync(bmp);
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const offset = view.getUint32(10, true);
  const width = view.getInt32(18, true);
  const height = view.getInt32(22, true);
  const bpp = view.getUint16(28, true);
  // sips picks 32 bpp only when the source has an alpha channel, 24 bpp otherwise.
  if (bpp !== 24 && bpp !== 32) {
    throw new Error(`BMP inattendu (${bpp} bpp) pour ${path}`);
  }
  const w = Math.abs(width);
  const h = Math.abs(height);
  if (w < HASH_WIDTH || h < HASH_HEIGHT) {
    throw new Error(`image trop petite (${w}×${h}, minimum ${HASH_WIDTH}×${HASH_HEIGHT}) : ${path}`);
  }

  const bytesPerPixel = bpp / 8;
  // BMP rows are padded to a 4-byte boundary.
  const rowBytes = Math.ceil((bpp * w) / 32) * 4;
  // A negative height means the rows are stored top-down.
  const topDown = height < 0;

  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const srcRow = topDown ? y : h - 1 - y;
    for (let x = 0; x < w; x++) {
      const src = offset + srcRow * rowBytes + x * bytesPerPixel;
      const dst = (y * w + x) * 4;
      // sips writes BGR(A); grayFromRGBA expects RGBA.
      rgba[dst] = data[src + 2] ?? 0;
      rgba[dst + 1] = data[src + 1] ?? 0;
      rgba[dst + 2] = data[src] ?? 0;
      rgba[dst + 3] = bpp === 32 ? data[src + 3] ?? 255 : 255;
    }
  }
  return { rgba, width: w, height: h };
}

/**
 * One-line JSON with a space after every `:` and `,` — the style the registry is
 * written in. `JSON.stringify` emits neither, so writing with it reformatted all
 * 36 entries and turned a one-line addition into a whole-file diff, on the one
 * file where a reviewer most needs to see exactly what changed.
 */
function inline(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(inline).join(", ")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value)
      .map(([k, v]) => `${JSON.stringify(k)}: ${inline(v)}`)
      .join(", ")}}`;
  }
  return JSON.stringify(value);
}

function hashFile(path: string): string {
  const { rgba, width, height } = pixels(path);
  const gray = grayFromRGBA(rgba, width, height);
  const hash = gray && dhash(gray);
  if (!hash) throw new Error(`échantillonnage impossible pour ${path}`);
  return hash;
}

// ---------------------------------------------------------------------------

const args = process.argv.slice(2);
const write = args[0] === "--write";
const [brandArg, ...images] = write ? args.slice(1) : args;

if (!brandArg || images.length === 0) {
  console.error("usage: bun run scripts/hash-logos.ts [--write] <marque> <image…>");
  process.exit(2);
}

const registry = JSON.parse(readFileSync(REGISTRY, "utf8")) as Entry[];
const entry = registry.find(
  (e) => fold(e.brand) === fold(brandArg) || e.aliases.some((a) => fold(a) === fold(brandArg)),
);
if (!entry) {
  console.error(`« ${brandArg} » n'est pas dans ${REGISTRY} — ajoutez la marque d'abord.`);
  process.exit(1);
}

const hashes: string[] = [];
for (const image of images) {
  const hash = hashFile(image);
  hashes.push(hash);
  console.log(`${hash}  ${image}`);
}

if (write) {
  const merged = [...new Set([...(entry.logo_hashes ?? []), ...hashes])].sort();
  entry.logo_hashes = merged;
  // Keep the one-entry-per-line formatting the registry uses (readable diffs).
  const body = registry.map((e) => `  ${inline(e)}`).join(",\n");
  writeFileSync(REGISTRY, `[\n${body}\n]\n`);
  console.log(`\n${entry.brand} : ${merged.length} empreinte(s) dans ${REGISTRY}`);
} else {
  console.log("\n(--write pour les enregistrer dans le registre)");
}
