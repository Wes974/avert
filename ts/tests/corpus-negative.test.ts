import "./setup";
import { describe, expect, test } from "bun:test";

import { detectCapturePoints } from "../src/l0";
import { analyzeUrl } from "../src/l1";
import { analyzePage } from "../src/l2";
import { BRANDS } from "../src/generated/brands";

// Weights mirror ScoreEngine.swift §5. Keep in sync (M6 will move both to a
// shared registry/weights.json). The test's real job is the signal set, not
// the exact arithmetic.
const WEIGHTS: Record<string, number> = {
  "l1.homograph": 35, "l1.punycode": 15, "l1.mixed-script": 20,
  "l1.typosquat": 30, "l1.combosquat": 20, "l1.brand-subdomain": 25,
  "l1.ip-literal": 15, "l1.exotic-port": 10, "l1.subdomain-depth": 10,
  "l1.low-rep-tld": 5,
  "l2.cross-origin-form": 25, "l2.hidden-capture-field": 30,
  "l2.thirdparty-iframe": 10, "l2.anti-inspection": 10,
  "l2.borrowed-brand-assets": 25,
};
const BANNER_THRESHOLD = 40;
const IDENTITY_SIGNALS = new Set([
  "l1.homograph", "l1.typosquat", "l1.brand-subdomain", "l2.borrowed-brand-assets",
]);

/** Build the dossier the way content.ts does, then score it the way Swift does. */
function assess(url: string, html: string) {
  document.body.innerHTML = html;
  const u = new URL(url);
  // happy-dom has no layout engine: getBoundingClientRect returns zeros, so
  // every field would look hidden. Force visible=true — visibility detection
  // is unit-tested separately with explicit fixtures (l0/l2 tests).
  const capturePoints = detectCapturePoints(document).map((p) => ({ ...p, visible: true }));
  const l1 = analyzeUrl(url, BRANDS);
  const l2 = analyzePage(document, u.host, capturePoints, BRANDS);
  const signals = [...l1, ...l2];
  const score = signals.reduce((s, sig) => s + (WEIGHTS[sig.id] ?? 0), 0);
  const identityMismatch = signals.some((s) => s.brand && IDENTITY_SIGNALS.has(s.id));
  return { score, identityMismatch, ids: signals.map((s) => s.id) };
}

// Real-world legitimate login/checkout shapes, including the tricky ones the
// PLAN flags: SSO redirects, 3-D Secure iframes, bank auth delegates.
const CORPUS: { name: string; url: string; html: string }[] = [
  {
    name: "Google account sign-in",
    url: "https://accounts.google.com/v3/signin/identifier",
    html: `<img alt="Google" src="/logo.png"><h1>Connexion</h1>
      <form action="/signin/challenge"><input type="email" name="identifier">
      <input type="password" name="password"></form>`,
  },
  {
    name: "Microsoft SSO (auth delegate host)",
    url: "https://login.microsoftonline.com/common/oauth2/authorize",
    html: `<img alt="Microsoft" src="/logo.svg"><h1>Se connecter</h1>
      <form action="/common/login"><input type="email" name="loginfmt">
      <input type="password" name="passwd"></form>`,
  },
  {
    name: "La Banque Postale — login posting to auth delegate wl-fr.com",
    url: "https://labanquepostale.fr/particulier.html",
    html: `<img alt="La Banque Postale" src="/lbp.png"><h1>Espace client</h1>
      <form action="https://auth.wl-fr.com/sso/login" method="post">
      <input type="text" name="user"><input type="password" name="pin"></form>`,
  },
  {
    name: "Amazon checkout with 3-D Secure iframe (card network)",
    url: "https://www.amazon.fr/gp/buy/payselect/handlers/display.html",
    html: `<h1>Paiement</h1>
      <iframe src="https://acs.cardinalcommerce.com/3ds/challenge" width="390" height="400"></iframe>
      <input autocomplete="cc-number" name="card">
      <input autocomplete="cc-csc" name="cvv">`,
  },
  {
    name: "Impots.gouv via FranceConnect (cross-origin to auth delegate)",
    url: "https://impots.gouv.fr/accueil",
    html: `<img alt="impots.gouv.fr" src="/dgfip.png"><h1>Votre espace particulier</h1>
      <form action="https://franceconnect.gouv.fr/api/v1/authorize">
      <input type="email" name="email"><input type="password" name="mdp"></form>`,
  },
  {
    name: "GitHub sign-in",
    url: "https://github.com/login",
    html: `<h1>Sign in to GitHub</h1><form action="/session">
      <input name="login"><input type="password" name="password"></form>`,
  },
  {
    name: "Boursobank with a marketing iframe from its own CDN",
    url: "https://boursobank.com/connexion/",
    html: `<img alt="BoursoBank" src="/logo.svg"><h1>Connexion</h1>
      <iframe src="https://boursobank.com/promo" width="300" height="250"></iframe>
      <form action="/connexion/valider"><input name="id">
      <input type="password" name="pw"></form>`,
  },
  {
    name: "Generic SaaS login, unknown brand, clean structure",
    url: "https://app.some-saas-tool.com/login",
    html: `<h1>Log in to Acme Tools</h1><form action="/auth/login">
      <input type="email" name="email"><input type="password" name="password"></form>`,
  },
];

describe("Negative corpus — ZERO strong alert on legitimate pages", () => {
  for (const page of CORPUS) {
    test(page.name, () => {
      const r = assess(page.url, page.html);
      // The load-bearing invariant: never a confirmed identity mismatch, never
      // a score that crosses the banner threshold.
      expect(r.identityMismatch, `identity mismatch on legit page — signals: ${r.ids}`).toBe(false);
      expect(r.score, `score ${r.score} ≥ ${BANNER_THRESHOLD} — signals: ${r.ids}`).toBeLessThan(
        BANNER_THRESHOLD,
      );
    });
  }
});
