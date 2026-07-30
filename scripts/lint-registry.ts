// Linter for registry/brands.json — the single source of truth for identity
// comparison. A bad entry here does not crash anything: it silently makes a real
// brand unverifiable (missed phishing) or claims a host belongs to a brand it
// doesn't (false alarm on a legitimate site). Both are invisible without a check.
//
//   bun run scripts/lint-registry.ts [--strict]
//
// Errors fail the build. Warnings are judgement calls (short aliases, mostly);
// --strict turns them into errors.

import registry from "../registry/brands.json" with { type: "json" };
import { MATCH_THRESHOLD, hamming, isDiscriminative } from "../ts/src/dhash";

const STRICT = process.argv.includes("--strict");
const SECTORS = new Set([
  "banking", "payment", "tech", "ecommerce", "streaming", "social",
  "government", "logistics", "telecom", "energy", "insurance", "crypto", "transport",
]);
const HOST = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

const errors: string[] = [];
const warnings: string[] = [];

const fold = (s: string) =>
  s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim();

interface Entry {
  brand: string;
  aliases: string[];
  domains: string[];
  auth_delegates: string[];
  sector: string;
  region: string[];
  logo_hashes?: string[];
}

const entries = registry as Entry[];
if (!Array.isArray(entries)) {
  console.error("registry/brands.json must be an array");
  process.exit(1);
}

// Folded name → where it was first seen. Aliases share this namespace with brand
// names on purpose: `BrandRegistry.match` resolves both, so a collision makes the
// winner depend on file order.
const names = new Map<string, string>();
const domains = new Map<string, string>();
const logoHashes = new Map<string, string>();

for (const [i, entry] of entries.entries()) {
  const at = `#${i} ${entry?.brand ?? "(sans nom)"}`;

  for (const key of ["brand", "sector"] as const) {
    if (typeof entry[key] !== "string" || entry[key].trim() === "") {
      errors.push(`${at}: champ « ${key} » manquant ou vide`);
    }
  }
  for (const key of ["aliases", "domains", "auth_delegates", "region"] as const) {
    if (!Array.isArray(entry[key])) errors.push(`${at}: champ « ${key} » doit être un tableau`);
  }
  if (errors.length > 0 && !entry.domains) continue;

  if (!SECTORS.has(entry.sector)) {
    errors.push(`${at}: secteur inconnu « ${entry.sector} » (attendus : ${[...SECTORS].join(", ")})`);
  }
  if (entry.region.length === 0) errors.push(`${at}: « region » ne peut pas être vide`);
  if (entry.domains.length === 0) {
    errors.push(`${at}: aucun domaine — la marque serait invérifiable`);
  }

  for (const name of [entry.brand, ...entry.aliases]) {
    if (typeof name !== "string" || name.trim() === "") {
      errors.push(`${at}: alias vide`);
      continue;
    }
    const key = fold(name);
    const seen = names.get(key);
    if (seen === at) {
      // Same entry: an unaccented or recased spelling of its own name. Harmless,
      // just dead weight — `match` already folds diacritics and case.
      warnings.push(`${at}: alias « ${name} » redondant (déjà couvert par la normalisation)`);
    } else if (seen) {
      errors.push(`${at}: « ${name} » entre en collision avec ${seen} (match ambigu)`);
    } else {
      names.set(key, at);
    }
    if (key.length <= 2) {
      warnings.push(`${at}: alias « ${name} » très court — risque de faux positif d'identité`);
    }
  }

  for (const domain of entry.domains) {
    if (!HOST.test(domain)) {
      errors.push(`${at}: domaine mal formé « ${domain} » (hôte nu, minuscules, sans schéma ni chemin)`);
      continue;
    }
    const seen = domains.get(domain);
    if (seen) errors.push(`${at}: domaine « ${domain} » déjà déclaré par ${seen}`);
    else domains.set(domain, at);
  }

  // Logo references: a malformed or uninformative hash is worse than none. A bad
  // one either matches nothing (silent miss) or, if near-uniform, matches every
  // flat image — which is why `isDiscriminative` gates them at runtime too.
  for (const hash of entry.logo_hashes ?? []) {
    if (!/^[0-9a-f]{16}$/.test(hash)) {
      errors.push(`${at}: empreinte de logo mal formée « ${hash} » (16 caractères hex minuscules)`);
      continue;
    }
    if (!isDiscriminative(hash)) {
      errors.push(`${at}: empreinte « ${hash} » trop uniforme — image quasi vide, elle matcherait n'importe quoi`);
    }
    // Equality is not the bar — `matchLogo` accepts anything within
    // MATCH_THRESHOLD bits, so two *near* hashes belonging to different brands
    // are just as indistinguishable, and whichever entry comes first in the file
    // wins. Checking only for exact duplicates let that through silently.
    let clash: string | null = null;
    for (const [other, owner] of logoHashes) {
      if (owner === at) continue;
      const distance = hamming(hash, other);
      if (distance !== null && distance <= MATCH_THRESHOLD) {
        clash = `${owner} (« ${other} », distance ${distance} ≤ ${MATCH_THRESHOLD})`;
        break;
      }
    }
    if (clash) {
      errors.push(`${at}: empreinte « ${hash} » indistinguable de celle de ${clash}`);
    } else {
      logoHashes.set(hash, at);
    }
  }

  for (const delegate of entry.auth_delegates) {
    const bare = delegate.startsWith("*.") ? delegate.slice(2) : delegate;
    if (!HOST.test(bare)) {
      errors.push(`${at}: délégué d'auth mal formé « ${delegate} » (attendu : hôte ou *.hôte)`);
    }
    // A delegate that is also someone's own domain would exempt a real mismatch.
    const owner = domains.get(bare);
    if (owner && owner !== at) {
      warnings.push(`${at}: délégué « ${delegate} » est le domaine de ${owner}`);
    }
  }
}

for (const w of warnings) console.warn(`⚠︎ ${w}`);
for (const e of errors) console.error(`✘ ${e}`);

const failed = errors.length > 0 || (STRICT && warnings.length > 0);
console.log(
  failed
    ? `registre invalide : ${errors.length} erreur(s), ${warnings.length} avertissement(s)`
    : `registre OK : ${entries.length} marques, ${domains.size} domaines, ` +
      `${logoHashes.size} empreinte(s) de logo, ${warnings.length} avertissement(s)`,
);
process.exit(failed ? 1 : 0);
