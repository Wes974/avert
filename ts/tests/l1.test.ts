import { describe, expect, test } from "bun:test";
import {
  analyzeUrl,
  levenshtein,
  normalizeConfusables,
  punycodeDecode,
  registrableDomain,
} from "../src/l1";
import { BRANDS } from "../src/generated/brands";

const ids = (url: string) => analyzeUrl(url, BRANDS).map((s) => s.id);
const brandsOf = (url: string) =>
  analyzeUrl(url, BRANDS).flatMap((s) => (s.brand ? [s.brand] : []));

describe("primitives", () => {
  test("punycode decode (RFC 3492 vector)", () => {
    expect(punycodeDecode("bcher-kva")).toBe("bücher");
  });

  test("levenshtein with cutoff", () => {
    expect(levenshtein("paypal", "paypal", 2)).toBe(0);
    expect(levenshtein("paypall", "paypal", 2)).toBe(1);
    expect(levenshtein("goggle", "google", 2)).toBe(1);
    expect(levenshtein("completely", "different", 2)).toBeGreaterThan(2);
  });

  test("confusable folding", () => {
    expect(normalizeConfusables("раураl")).toBe("paypal"); // Cyrillic р, а, у
    expect(normalizeConfusables("paypa1")).toBe("paypal");
  });

  test("registrable domain", () => {
    expect(registrableDomain("accounts.google.com")).toBe("google.com");
    expect(registrableDomain("impots.gouv.fr")).toBe("impots.gouv.fr");
    expect(registrableDomain("evil.co.uk")).toBe("evil.co.uk");
    expect(registrableDomain("a.b.evil.co.uk")).toBe("evil.co.uk");
  });
});

describe("L1 malicious patterns", () => {
  test("homograph SLD (IDN)", () => {
    // Cyrillic 'а' in "аpple.com" — URL() punycodes it, we decode it back.
    expect(ids("https://аpple.com/login")).toContain("l1.homograph");
    expect(brandsOf("https://аpple.com/login")).toContain("Apple");
  });

  test("digit-substitution homograph", () => {
    expect(brandsOf("https://paypa1.com")).toContain("PayPal");
  });

  test("typosquat", () => {
    expect(ids("https://paypall.com")).toContain("l1.typosquat");
    expect(ids("https://goggle.com")).toContain("l1.typosquat");
  });

  test("combosquat", () => {
    const sigs = ids("https://apple-verification-secure.com");
    expect(sigs).toContain("l1.combosquat");
  });

  test("brand in subdomain of foreign domain", () => {
    const url = "https://paypal.com.session-verify.xyz/signin";
    expect(ids(url)).toContain("l1.brand-subdomain");
    expect(ids(url)).toContain("l1.low-rep-tld");
  });

  test("IP literal and exotic port", () => {
    expect(ids("http://192.168.12.10/login")).toContain("l1.ip-literal");
    expect(ids("https://evil-portal.com:8443/")).toContain("l1.exotic-port");
  });

  test("excessive subdomain depth", () => {
    expect(ids("https://a.b.c.d.example.com")).toContain("l1.subdomain-depth");
  });

  test("punycode flagged even without brand match", () => {
    expect(ids("https://xn--bcher-kva.com")).toContain("l1.punycode");
  });
});

describe("L1 false-positive guard (the priority metric)", () => {
  const legit = [
    "https://accounts.google.com/signin",
    "https://www.amazon.fr/ap/signin",
    "https://login.microsoftonline.com/common/oauth2",
    "https://particuliers.sg.fr/",
    "https://www.labanquepostale.fr/espace-client",
    "https://impots.gouv.fr/accueil",
    "https://app.franceconnect.gouv.fr/",
    "https://www.icloud.com/",
    "https://github.com/login",
    "https://www.chronopost.fr/fr/suivi",
  ];
  for (const url of legit) {
    test(`no signal on ${url}`, () => {
      expect(analyzeUrl(url, BRANDS)).toEqual([]);
    });
  }
});
