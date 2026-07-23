import { beforeAll, describe, expect, test } from "bun:test";
import { GlobalRegistrator } from "@happy-dom/global-registrator";

beforeAll(() => {
  if (typeof document === "undefined") {
    GlobalRegistrator.register({ url: "https://test.example/" });
  }
});

import { analyzePage } from "../src/l2";
import { BRANDS } from "../src/generated/brands";
import type { CapturePoint } from "../src/types";

const visiblePassword: CapturePoint = {
  kind: "password",
  visible: true,
  inIframe: false,
  crossOriginActionHost: null,
};

function docFrom(html: string): Document {
  document.body.innerHTML = html;
  return document;
}

const ids = (
  html: string,
  host: string,
  points: CapturePoint[] = [visiblePassword],
) => analyzePage(docFrom(html), host, points, BRANDS).map((s) => s.id);

describe("L2 signals", () => {
  test("cross-origin form action", () => {
    const points: CapturePoint[] = [
      { ...visiblePassword, crossOriginActionHost: "collector.evil.example" },
    ];
    expect(ids("<p>x</p>", "victim.example", points)).toContain("l2.cross-origin-form");
  });

  test("hidden capture field", () => {
    const points: CapturePoint[] = [{ ...visiblePassword, visible: false }];
    expect(ids("<p>x</p>", "victim.example", points)).toContain("l2.hidden-capture-field");
  });

  test("large third-party iframe", () => {
    const html = '<iframe src="https://unknown-third.example/box" width="400" height="300"></iframe>';
    expect(ids(html, "victim.example")).toContain("l2.thirdparty-iframe");
  });

  test("anti-inspection inline handlers", () => {
    document.body.setAttribute("oncontextmenu", "return false");
    const sigs = analyzePage(document, "victim.example", [visiblePassword], BRANDS);
    document.body.removeAttribute("oncontextmenu");
    expect(sigs.map((s) => s.id)).toContain("l2.anti-inspection");
  });

  test("borrowed brand favicon", () => {
    document.head.innerHTML = '<link rel="icon" href="https://www.paypal.com/favicon.ico">';
    const sigs = analyzePage(docFrom("<p>x</p>"), "secure-pp.example", [visiblePassword], BRANDS);
    document.head.innerHTML = "";
    const borrowed = sigs.find((s) => s.id === "l2.borrowed-brand-assets");
    expect(borrowed?.brand).toBe("PayPal");
  });

  test("clean page yields nothing", () => {
    document.head.innerHTML = "";
    expect(ids('<form action="/login"><input type="password"></form>', "victim.example")).toEqual(
      [],
    );
  });
});
