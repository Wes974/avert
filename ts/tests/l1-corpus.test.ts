import { describe, expect, test } from "bun:test";
import { analyzeUrl } from "../src/l1";
import { BRANDS } from "../src/generated/brands";
import corpus from "../../Tests/corpus/l1.json" with { type: "json" };

// Half of the anti-drift harness: the same corpus is asserted from Swift in
// Tests/Swift/URLHeuristicsTests.swift. Two engines implement L1 (the extension
// in TS, the App Intent in Swift) and they must agree, or a link checked from a
// text message and the same link opened in Safari would give different answers.

interface Case {
  url: string;
  expect: string[];
  expectSwift?: string[];
  note?: string;
}

const cases = corpus.cases as Case[];

function signalKeys(url: string): string[] {
  return analyzeUrl(url, BRANDS)
    .map((s) => s.id + (s.brand ? `@${s.brand}` : ""))
    .sort();
}

describe("corpus L1 (partagé avec Swift)", () => {
  test("le corpus est non vide et bien formé", () => {
    expect(cases.length).toBeGreaterThan(15);
    for (const c of cases) {
      expect(typeof c.url).toBe("string");
      expect(Array.isArray(c.expect)).toBe(true);
    }
  });

  for (const c of cases) {
    test(`${c.url} → [${c.expect.join(", ")}]`, () => {
      expect(signalKeys(c.url)).toEqual([...c.expect].sort());
    });
  }

  test("aucune alerte sur les domaines légitimes du corpus", () => {
    // The load-bearing property: a brand's own domain, and its auth delegates,
    // must produce nothing at all.
    const legit = cases.filter((c) => c.expect.length === 0 && !c.expectSwift);
    expect(legit.length).toBeGreaterThanOrEqual(4);
    for (const c of legit) expect(signalKeys(c.url)).toEqual([]);
  });
});
