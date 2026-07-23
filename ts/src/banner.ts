import type { Verdict } from "./types";

// First discreet banner (M2). Shadow DOM so page CSS can't restyle or hide it
// trivially; deliberately non-blocking and dismissible (PLAN.md §6). The
// full-screen interstitial arrives in M5.

export function showBanner(verdict: Verdict): void {
  if (document.getElementById("impostor-banner-host")) return;

  const host = document.createElement("div");
  host.id = "impostor-banner-host";
  const shadow = host.attachShadow({ mode: "closed" });

  const bar = document.createElement("div");
  bar.setAttribute(
    "style",
    [
      "position:fixed", "top:0", "left:0", "right:0", "z-index:2147483647",
      "display:flex", "align-items:center", "gap:8px",
      "padding:10px 14px", "font:14px -apple-system,system-ui,sans-serif",
      "background:#8a2e00", "color:#fff",
      "box-shadow:0 2px 8px rgba(0,0,0,.35)",
    ].join(";"),
  );

  const text = document.createElement("span");
  text.style.flex = "1";
  text.textContent =
    verdict.reason ??
    "Impostor : cette page présente plusieurs caractéristiques de page de phishing. Vérifiez l'adresse avant de saisir quoi que ce soit.";

  const close = document.createElement("button");
  close.textContent = "Ignorer";
  close.setAttribute(
    "style",
    "background:transparent;border:1px solid #fff;color:#fff;border-radius:6px;padding:4px 10px;font:13px -apple-system,system-ui,sans-serif",
  );
  close.addEventListener("click", () => host.remove());

  bar.append(text, close);
  shadow.append(bar);
  document.documentElement.append(host);
}
