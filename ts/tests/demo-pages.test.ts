import "./setup";
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { BRANDS } from "../src/generated/brands";
import { detectCapturePoints } from "../src/l0";
import { analyzeUrl } from "../src/l1";
import { analyzePage } from "../src/l2";

// The public demo pages (docs/demo/) are how someone who is not us finds out
// whether Avert works. If a change to the engine quietly stops them tripping,
// the failure looks like "the app is broken" to a tester and we would hear it
// as a bug report, not as a regression.
//
// So the pages are pinned here: the exact signals each one must produce, from
// the files that are actually published. `logo.ts` is absent by necessity —
// hashing needs a canvas rasteriser that happy-dom does not have — so the logo
// signal of the second page is covered by the Swift side and by the registry
// linter instead.

const DOCS = join(import.meta.dir, "..", "..", "docs");
const HOST = "wes974.github.io";

function load(page: string): Document {
  const html = readFileSync(join(DOCS, "demo", page, "index.html"), "utf8");
  // Only the body. Injecting the whole document makes happy-dom resolve the
  // <link rel=stylesheet>, i.e. issue a real HTTP request from the test suite of
  // an app whose central guarantee is that it never makes one. Everything these
  // tests assert on — forms, inputs, the logo — lives in the body, and the
  // hidden field's `display:none` is an inline attribute, so it survives.
  const body = /<body[^>]*>([\s\S]*)<\/body>/i.exec(html);
  if (!body?.[1]) throw new Error(`pas de <body> dans docs/demo/${page}/index.html`);
  // innerHTML does not execute <script>, here as in a browser: we analyse the
  // page as served, before any of its own JavaScript has run.
  document.body.innerHTML = body[1];
  return document;
}

function signals(page: string) {
  const doc = load(page);
  const points = detectCapturePoints(doc);
  return {
    points,
    l1: analyzeUrl(`https://${HOST}/avert/demo/${page}/`, BRANDS).map((s) => s.id),
    l2: analyzePage(doc, HOST, points, BRANDS).map((s) => s.id),
  };
}

describe("published demo pages", () => {
  test("page 1 trips a banner, and cannot reach an interstitial", () => {
    const { points, l1, l2 } = signals("alerte");

    expect(points.length).toBeGreaterThanOrEqual(2);
    expect(points.every((p) => p.kind === "password")).toBe(true);
    expect(l2).toContain("l2.cross-origin-form");
    expect(l2).toContain("l2.hidden-capture-field");

    // 25 + 30 = 55: over the banner threshold, under the interstitial one — and
    // with no brand in play there is no ×2 to lift it there either. This page
    // demonstrates the weak alert on purpose; see page 2 for the strong one.
    const identitySignals = [...l1, ...l2].filter((id) =>
      ["l1.homograph", "l1.typosquat", "l1.brand-subdomain", "l2.borrowed-brand-assets"].includes(id),
    );
    expect(identitySignals).toEqual([]);
  });

  test("page 2 adds the two non-logo signals the strong alert needs", () => {
    const { points, l2 } = signals("interstitiel");

    expect(l2).toContain("l2.cross-origin-form");
    expect(l2).toContain("l2.hidden-capture-field");
    expect(points.some((p) => p.crossOriginActionHost === "collect.invalid")).toBe(true);
  });

  test("page 2's logo is same-origin, or it can never be hashed", () => {
    // A cross-origin image taints the canvas and `logo.ts` skips it. Writing the
    // logo as an absolute URL — an easy edit to make — would silently disarm the
    // one signal this page exists to demonstrate.
    load("interstitiel");
    const src = document.querySelector("img.logo")?.getAttribute("src") ?? "";
    expect(src).toBe("logo.png");
  });

  test("neither page can submit anything anywhere", () => {
    // The pages imitate a login form. The guarantee that nothing typed into one
    // can leave the browser is not a comment, it is this assertion.
    for (const page of ["alerte", "interstitiel"]) {
      load(page);
      const actions = [...document.querySelectorAll("form")].map((f) => f.getAttribute("action"));
      expect(actions.length).toBeGreaterThan(0);
      for (const action of actions) {
        expect(new URL(action ?? "").hostname.endsWith(".invalid")).toBe(true);
      }
    }
  });
});
