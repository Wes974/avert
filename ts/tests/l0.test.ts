import "./setup";
import { describe, expect, test } from "bun:test";
import { classifyInput } from "../src/l0";

function el(html: string): Element {
  document.body.innerHTML = html;
  const e = document.body.firstElementChild;
  if (!e) throw new Error("no element");
  return e;
}

describe("L0 capture-point classification", () => {
  test("password field", () => {
    expect(classifyInput(el('<input type="password" name="pass">'))).toBe("password");
  });

  test("payment card via autocomplete and via attributes", () => {
    expect(classifyInput(el('<input autocomplete="cc-number">'))).toBe("payment-card");
    expect(classifyInput(el('<input name="cardNumber">'))).toBe("payment-card");
    expect(classifyInput(el('<input placeholder="Cryptogramme">'))).toBe("payment-card");
  });

  test("OTP via autocomplete and via attributes", () => {
    expect(classifyInput(el('<input autocomplete="one-time-code">'))).toBe("otp");
    expect(classifyInput(el('<input name="otp" maxlength="6">'))).toBe("otp");
    expect(classifyInput(el('<input name="verification_code" inputmode="numeric">'))).toBe("otp");
  });

  test("seed phrase", () => {
    expect(classifyInput(el('<textarea name="recovery-phrase"></textarea>'))).toBe("seed-phrase");
    expect(classifyInput(el('<input placeholder="Mnemonic">'))).toBe("seed-phrase");
  });

  test("identity document upload", () => {
    expect(classifyInput(el('<input type="file" name="passport_scan">'))).toBe(
      "id-document-upload",
    );
  });

  test("ordinary inputs are ignored", () => {
    expect(classifyInput(el('<input type="text" name="search">'))).toBeNull();
    expect(classifyInput(el('<input type="email" name="email">'))).toBeNull();
    expect(classifyInput(el('<input type="file" name="avatar">'))).toBeNull();
  });
});
