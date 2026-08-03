import "./setup";
import { afterAll, describe, expect, test } from "bun:test";

import { BRANDS } from "../src/generated/brands";
import { IDENTITY_SIGNALS, SCORING, WEIGHTS } from "../src/generated/scoring";
import { classifyInput, detectCapturePoints } from "../src/l0";
import { analyzeUrl } from "../src/l1";
import { analyzePage } from "../src/l2";
import { CASES, type Verdict } from "./corpus/cases";

// Evaluation harness (#44). Two jobs, and the second is the reason it exists:
//
//   1. Pin current behaviour, so a change in detection shows up as a failing
//      test instead of drifting unnoticed.
//   2. Count the KNOWN GAPS — cases whose goal differs from what the engine does
//      today — and print them. A corpus that only holds what already works says
//      nothing about what is missing.
//
// This must run before any change to the detection model (#45): without a
// before/after measurement, widening the engine is a bet. It is also what makes
// the false-positive risk visible, and false positives are what would actually
// sink this product.

/**
 * Builds the dossier the way content.ts does, then scores it the way
 * ScoreEngine.swift does — from the same registry/scoring.json both read.
 *
 * The logo signal is absent by necessity: hashing needs a canvas rasteriser
 * that happy-dom does not have. Cases relying on it are covered on the Swift
 * side and by the registry linter.
 */
function assess(url: string, html: string) {
  document.body.innerHTML = html;
  const host = new URL(url).host;
  // happy-dom has no layout engine: getBoundingClientRect returns zeros, so
  // isVisible() would report every field as hidden and l2.hidden-capture-field
  // would fire on every single case. Visibility is therefore decided here, from
  // the inline style the fixture declares — which is exactly what the cases
  // exercising that signal write.
  //
  // The two lists line up because both walk querySelectorAll in document order
  // and apply the same classifier.
  const classified = [...document.querySelectorAll("input, textarea")].filter((el) =>
    classifyInput(el),
  );
  const points = detectCapturePoints(document).map((p, i) => ({
    ...p,
    visible: !/display:\s*none/i.test(classified[i]?.getAttribute("style") ?? ""),
  }));

  const l1 = analyzeUrl(url, BRANDS);
  const l2 = analyzePage(document, host, points, BRANDS);
  const signals = [...l1, ...l2];

  const contributing = signals.filter((s) => (WEIGHTS[s.id] ?? 0) > 0);
  let score = contributing.reduce((sum, s) => sum + (WEIGHTS[s.id] ?? 0), 0);
  const identityMismatch = signals.some((s) => s.brand && IDENTITY_SIGNALS.has(s.id));
  if (identityMismatch) score *= SCORING.identityMultiplier;

  let verdict: Verdict;
  if (contributing.length < SCORING.minimumConvergingSignals) verdict = "silent";
  else if (score > SCORING.thresholds.interstitial && identityMismatch) verdict = "interstitial";
  else if (score >= SCORING.thresholds.banner) verdict = "banner";
  else verdict = "silent";

  return { verdict, score, identityMismatch, ids: signals.map((s) => s.id) };
}

const results = CASES.map((c) => ({ case: c, result: assess(c.url, c.html) }));

describe("Corpus d'évaluation — comportement figé", () => {
  for (const { case: c, result } of results) {
    test(`${c.class} / ${c.id}`, () => {
      expect(
        result.verdict,
        `attendu ${c.current}, obtenu ${result.verdict} (score ${result.score}, signaux : ${result.ids.join(", ") || "aucun"})`,
      ).toBe(c.current);
    });
  }
});

describe("Invariant : zéro alerte forte sur une page légitime", () => {
  // The property everything else rests on. Kept as its own assertion rather than
  // folded into the pinning above: if a legitimate page ever raises a strong
  // alert, that is not a drift to acknowledge, it is a defect to stop the build.
  for (const { case: c, result } of results.filter((r) => r.case.class === "legit")) {
    test(c.id, () => {
      expect(result.identityMismatch, `incohérence d'identité — signaux : ${result.ids}`).toBe(false);
      expect(result.verdict, `signaux : ${result.ids}`).not.toBe("interstitial");
    });
  }
});

afterAll(() => {
  const gaps = results.filter((r) => r.case.current !== r.case.goal);
  const positives = results.filter((r) => r.case.class !== "legit");
  const detected = positives.filter((r) => r.result.verdict !== "silent");

  const byClass = new Map<string, { n: number; detected: number }>();
  for (const r of positives) {
    const e = byClass.get(r.case.class) ?? { n: 0, detected: 0 };
    e.n += 1;
    if (r.result.verdict !== "silent") e.detected += 1;
    byClass.set(r.case.class, e);
  }

  const lines = [
    "",
    "── Corpus de détection ─────────────────────────────────",
    `  Cas : ${results.length}  (${positives.length} positifs, ${results.length - positives.length} légitimes)`,
    `  Détectés : ${detected.length}/${positives.length}`,
    `  Fausses alertes fortes : ${results.filter((r) => r.case.class === "legit" && r.result.verdict === "interstitial").length}`,
    "",
    "  Par classe :",
    ...[...byClass.entries()]
      .sort()
      .map(([k, v]) => `    ${v.detected === v.n ? "✓" : "✗"} ${k.padEnd(24)} ${v.detected}/${v.n}`),
    "",
    `  Trous connus (goal ≠ actuel) : ${gaps.length}`,
    ...gaps.map((g) => `    · ${g.case.id.padEnd(30)} ${g.case.current} → ${g.case.goal}`),
    "────────────────────────────────────────────────────────",
  ];
  console.log(lines.join("\n"));
});
