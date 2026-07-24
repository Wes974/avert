// L1 — URL heuristics (PLAN.md §3). Pure functions, no DOM, no network:
// everything here must be unit-testable from a bare URL string.

export interface BrandEntry {
  brand: string;
  aliases: string[];
  domains: string[];
  auth_delegates: string[];
  sector: string;
  region: string[];
  /** dHash references of the brand's logo (see dhash.ts). Optional: a brand with
   *  none simply isn't checked visually. */
  logo_hashes?: string[];
}

export interface L1Signal {
  id:
    | "l1.punycode"
    | "l1.homograph"
    | "l1.mixed-script"
    | "l1.typosquat"
    | "l1.combosquat"
    | "l1.brand-subdomain"
    | "l1.ip-literal"
    | "l1.exotic-port"
    | "l1.subdomain-depth"
    | "l1.low-rep-tld";
  detail?: string;
  /** Brand name from the registry when the signal implicates one. */
  brand?: string;
}

// ---------------------------------------------------------------------------
// Punycode decoding (RFC 3492), needed to inspect IDN labels offline.

const PUNY_BASE = 36;
const PUNY_TMIN = 1;
const PUNY_TMAX = 26;
const PUNY_SKEW = 38;
const PUNY_DAMP = 700;
const PUNY_INITIAL_BIAS = 72;
const PUNY_INITIAL_N = 128;

function punyAdapt(delta: number, numPoints: number, firstTime: boolean): number {
  delta = firstTime ? Math.floor(delta / PUNY_DAMP) : delta >> 1;
  delta += Math.floor(delta / numPoints);
  let k = 0;
  while (delta > ((PUNY_BASE - PUNY_TMIN) * PUNY_TMAX) >> 1) {
    delta = Math.floor(delta / (PUNY_BASE - PUNY_TMIN));
    k += PUNY_BASE;
  }
  return k + Math.floor(((PUNY_BASE - PUNY_TMIN + 1) * delta) / (delta + PUNY_SKEW));
}

/** Decode one punycode label (without the xn-- prefix). Returns null on malformed input. */
export function punycodeDecode(input: string): string | null {
  const output: number[] = [];
  let n = PUNY_INITIAL_N;
  let i = 0;
  let bias = PUNY_INITIAL_BIAS;

  const lastDelim = input.lastIndexOf("-");
  if (lastDelim > 0) {
    for (const ch of input.slice(0, lastDelim)) {
      const cp = ch.codePointAt(0) ?? 0;
      if (cp >= 0x80) return null;
      output.push(cp);
    }
  }

  let idx = lastDelim > 0 ? lastDelim + 1 : 0;
  while (idx < input.length) {
    const oldi = i;
    let w = 1;
    for (let k = PUNY_BASE; ; k += PUNY_BASE) {
      if (idx >= input.length) return null;
      const cp = input.codePointAt(idx++) ?? 0;
      const digit =
        cp >= 0x61 ? cp - 0x61 : cp >= 0x41 ? cp - 0x41 : cp >= 0x30 ? cp - 0x30 + 26 : -1;
      if (digit < 0 || digit >= PUNY_BASE) return null;
      i += digit * w;
      const t = k <= bias ? PUNY_TMIN : k >= bias + PUNY_TMAX ? PUNY_TMAX : k - bias;
      if (digit < t) break;
      w *= PUNY_BASE - t;
    }
    bias = punyAdapt(i - oldi, output.length + 1, oldi === 0);
    n += Math.floor(i / (output.length + 1));
    i %= output.length + 1;
    output.splice(i, 0, n);
    i++;
  }
  return String.fromCodePoint(...output);
}

// ---------------------------------------------------------------------------
// Script mixing & confusables.

const CYRILLIC = /[Ѐ-ӿ]/;
const GREEK = /[Ͱ-Ͽ]/;
const LATIN = /[a-z]/i;

export function hasMixedScript(label: string): boolean {
  const scripts = [CYRILLIC.test(label), GREEK.test(label), LATIN.test(label)];
  return scripts.filter(Boolean).length > 1;
}

// Common homoglyphs → ASCII. Deliberately small: only glyphs that are visually
// near-identical in a browser address bar.
const CONFUSABLES: Record<string, string> = {
  "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y",
  "і": "i", "ѕ": "s", "ԁ": "d", "ј": "j", "һ": "h", "ԛ": "q", "ԝ": "w",
  "ο": "o", "α": "a", "ν": "v", "ι": "i", "κ": "k", "τ": "t", "υ": "u",
  "0": "o", "1": "l", "3": "e", "5": "s", "7": "t",
};

export function normalizeConfusables(s: string): string {
  let out = "";
  for (const ch of s) out += CONFUSABLES[ch] ?? ch;
  return out;
}

// Exposed for a regression test: normalizeConfusables iterates code point by
// code point, so any key longer than one code point is dead (silent miss).
export const CONFUSABLE_KEYS = Object.keys(CONFUSABLES);

// ---------------------------------------------------------------------------
// Levenshtein with cutoff.

export function levenshtein(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      const v = Math.min((prev[j] ?? 0) + 1, (cur[j - 1] ?? 0) + 1, (prev[j - 1] ?? 0) + cost);
      cur.push(v);
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length] ?? max + 1;
}

// ---------------------------------------------------------------------------
// Registrable domain (approximate: common multi-label public suffixes only —
// a full PSL would be overkill for signal purposes).

const TWO_LEVEL_SUFFIXES = new Set([
  "co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "net.au", "org.au",
  "com.br", "com.mx", "com.ar", "co.jp", "co.in", "co.nz", "com.tr",
  "com.cn", "com.hk", "com.sg", "co.za", "gouv.fr", "asso.fr", "com.es",
]);

export function registrableDomain(host: string): string {
  const labels = host.toLowerCase().split(".");
  if (labels.length <= 2) return labels.join(".");
  const lastTwo = labels.slice(-2).join(".");
  const take = TWO_LEVEL_SUFFIXES.has(lastTwo) ? 3 : 2;
  return labels.slice(-take).join(".");
}

const LOW_REP_TLDS = new Set([
  "top", "xyz", "tk", "ml", "ga", "cf", "gq", "icu", "click", "link",
  "work", "rest", "fit", "loan", "men", "bid", "stream", "racing", "win",
  "party", "date", "faith", "review", "vip", "monster", "quest", "cyou",
]);

const COMBO_KEYWORDS = [
  "secure", "verif", "verification", "login", "signin", "sign-in", "account",
  "support", "update", "confirm", "wallet", "service", "auth", "id",
  "assistance", "client", "portail", "espace",
];

// ---------------------------------------------------------------------------

function brandTokens(brand: BrandEntry): string[] {
  // Tokens that identify the brand inside a domain: SLD of each brand domain.
  const tokens = new Set<string>();
  for (const d of brand.domains) {
    const sld = registrableDomain(d).split(".")[0];
    if (sld && sld.length >= 4) tokens.add(sld);
  }
  return [...tokens];
}

function isOwnedBy(host: string, brand: BrandEntry): boolean {
  const reg = registrableDomain(host);
  return (
    brand.domains.some((d) => reg === registrableDomain(d)) ||
    brand.auth_delegates.some((d) => {
      const clean = d.replace(/^\*\./, "");
      return reg === registrableDomain(clean) || host === clean;
    })
  );
}

export function analyzeUrl(rawUrl: string, brands: BrandEntry[]): L1Signal[] {
  const signals: L1Signal[] = [];
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return signals;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return signals;

  const host = url.hostname.toLowerCase();
  const labels = host.split(".");
  const reg = registrableDomain(host);
  const sld = reg.split(".")[0] ?? "";
  const tld = labels[labels.length - 1] ?? "";

  // If the page is on a domain a registry brand actually owns, L1 has nothing
  // to say about it (the whole point is low false positives on legit sites).
  const owner = brands.find((b) => isOwnedBy(host, b));
  if (owner) return signals;

  // --- IP literal / exotic port / structure
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.startsWith("[")) {
    signals.push({ id: "l1.ip-literal", detail: host });
  }
  if (url.port !== "" && url.port !== "80" && url.port !== "443") {
    signals.push({ id: "l1.exotic-port", detail: url.port });
  }
  if (labels.length >= 5) {
    signals.push({ id: "l1.subdomain-depth", detail: String(labels.length) });
  }
  if (LOW_REP_TLDS.has(tld)) {
    signals.push({ id: "l1.low-rep-tld", detail: tld });
  }

  // --- IDN / punycode / homographs
  const decodedLabels = labels.map((l) =>
    l.startsWith("xn--") ? (punycodeDecode(l.slice(4)) ?? l) : l,
  );
  const hadPunycode = labels.some((l) => l.startsWith("xn--"));
  if (hadPunycode) {
    signals.push({ id: "l1.punycode", detail: decodedLabels.join(".") });
  }
  const decodedHost = decodedLabels.join(".");
  if (decodedLabels.some(hasMixedScript)) {
    signals.push({ id: "l1.mixed-script", detail: decodedHost });
  }

  // --- Brand-implicating signals
  const normalizedSld = normalizeConfusables(
    registrableDomain(decodedHost).split(".")[0] ?? sld,
  );
  for (const brand of brands) {
    for (const token of brandTokens(brand)) {
      // Homograph: after confusable folding the SLD *is* the brand token.
      if (normalizedSld === token && sld !== token) {
        signals.push({ id: "l1.homograph", detail: `${sld} → ${token}`, brand: brand.brand });
        continue;
      }
      // Typosquat: small edit distance on the SLD.
      const maxDist = token.length >= 8 ? 2 : 1;
      const dist = levenshtein(normalizedSld, token, maxDist);
      if (dist > 0 && dist <= maxDist) {
        signals.push({ id: "l1.typosquat", detail: `${sld} ≈ ${token}`, brand: brand.brand });
        continue;
      }
      // Combosquat: brand token embedded in a longer SLD with a lure keyword,
      // or brand token + anything hyphenated.
      if (normalizedSld !== token && normalizedSld.includes(token)) {
        const rest = normalizedSld.replace(token, "");
        const luring = COMBO_KEYWORDS.some((k) => normalizedSld.includes(k)) || rest.includes("-");
        if (luring) {
          signals.push({ id: "l1.combosquat", detail: sld, brand: brand.brand });
          continue;
        }
      }
      // Brand as subdomain of a foreign domain: paypal.com.evil.xyz,
      // login-paypal.evil.top…
      const subLabels = decodedLabels.slice(0, -reg.split(".").length);
      if (subLabels.some((l) => normalizeConfusables(l).includes(token))) {
        signals.push({ id: "l1.brand-subdomain", detail: host, brand: brand.brand });
      }
    }
  }

  // Dedup identical (id, brand) pairs.
  const seen = new Set<string>();
  return signals.filter((s) => {
    const key = `${s.id}|${s.brand ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
