import { describe, expect, test } from "bun:test";
import {
  frameSignals,
  pageSignature,
  synthesizeFramePoints,
  type FrameCapture,
} from "../src/frames";
import { BRANDS } from "../src/generated/brands";
import type { CapturePoint } from "../src/types";

const stripe: FrameCapture = { frameHost: "js.stripe.com", kinds: ["payment-card"] };

describe("frame capture merge", () => {
  test("subframe capture points are flagged inIframe and deduplicated", () => {
    const points = synthesizeFramePoints([
      { frameHost: "collect.evil.example", kinds: ["password", "password", "otp"] },
    ]);
    expect(points).toHaveLength(2);
    expect(points.every((p) => p.inIframe)).toBe(true);
    // Never inferred from a frame report — the action host is the subframe's own
    // business, and guessing it would fabricate a cross-origin-form signal.
    expect(points.every((p) => p.crossOriginActionHost === null)).toBe(true);
  });

  test("a foreign frame collecting a secret raises one signal", () => {
    const signals = frameSignals([stripe], "boutique.example", BRANDS);
    expect(signals.map((s) => s.id)).toEqual(["l2.capture-in-thirdparty-iframe"]);
    expect(signals[0]?.detail).toBe("js.stripe.com");
  });

  test("same-site frames are exempt", () => {
    const signals = frameSignals(
      [{ frameHost: "checkout.boutique.example", kinds: ["payment-card"] }],
      "www.boutique.example",
      BRANDS,
    );
    expect(signals).toEqual([]);
  });

  test("a frame owned by the page's own brand is exempt (delegated auth)", () => {
    // La Banque Postale delegates authentication to *.wl-fr.com in the registry.
    const signals = frameSignals(
      [{ frameHost: "auth.wl-fr.com", kinds: ["password"] }],
      "www.labanquepostale.fr",
      BRANDS,
    );
    expect(signals).toEqual([]);
  });

  test("an empty report raises nothing", () => {
    expect(frameSignals([{ frameHost: "ads.example", kinds: [] }], "site.example", BRANDS))
      .toEqual([]);
  });

  test("the signal alone can never alert", () => {
    // Weight 15 in ScoreEngine + thirdparty-iframe 10 = 25, under the 40 banner
    // threshold. Locked here so a future reweighting has to face the test.
    const signals = frameSignals([stripe], "boutique.example", BRANDS);
    expect(signals).toHaveLength(1);
  });
});

describe("page signature", () => {
  const password: CapturePoint = {
    kind: "password",
    visible: true,
    inIframe: false,
    crossOriginActionHost: null,
  };

  test("stable for an unchanged state, whatever the point order", () => {
    const a = pageSignature("site.example", "/login", [password, { ...password, kind: "otp" }]);
    const b = pageSignature("site.example", "/login", [{ ...password, kind: "otp" }, password]);
    expect(a).toBe(b);
  });

  test("changes on SPA route change", () => {
    expect(pageSignature("site.example", "/login", [password]))
      .not.toBe(pageSignature("site.example", "/account", [password]));
  });

  test("distinguishes a capture point in an iframe from one in the page", () => {
    expect(pageSignature("site.example", "/", [password]))
      .not.toBe(pageSignature("site.example", "/", [{ ...password, inIframe: true }]));
  });
});
