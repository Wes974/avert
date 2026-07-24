import type { Verdict } from "./types";

// Alert UI (PLAN.md §6): discreet banner for the 40–70 band, full-screen
// interstitial above 70 with confirmed identity mismatch. Both live in a
// closed shadow DOM so page CSS can't restyle or hide them, both always keep
// an escape hatch — an extension that blocks with no recourse gets uninstalled.

const HOST_ID = "impostor-ui-host";

function ensureHost(): ShadowRoot | null {
  if (document.getElementById(HOST_ID)) return null;
  const host = document.createElement("div");
  host.id = HOST_ID;
  const shadow = host.attachShadow({ mode: "closed" });
  document.documentElement.append(host);
  return shadow;
}

function removeHost(): void {
  document.getElementById(HOST_ID)?.remove();
}

const FALLBACK_REASON =
  "Cette page présente plusieurs caractéristiques de page de phishing. Vérifiez l'adresse avant de saisir quoi que ce soit.";

// Bring-up only (removed in M6): shows the L3 state so we can read it off the
// device screen while os_log .info isn't reachable via idevicesyslog.
function debugLine(text: string): HTMLElement {
  const el = document.createElement("div");
  el.setAttribute(
    "style",
    "margin-top:16px;padding-top:12px;border-top:1px solid #333;font:12px ui-monospace,monospace;color:#7a7a7e;word-break:break-word",
  );
  el.textContent = text;
  return el;
}

export function showBanner(verdict: Verdict): void {
  const shadow = ensureHost();
  if (!shadow) return;

  const bar = document.createElement("div");
  bar.setAttribute(
    "style",
    [
      "position:fixed", "top:0", "left:0", "right:0", "z-index:2147483647",
      "display:flex", "align-items:center", "gap:8px",
      "padding:10px 14px", "font:14px -apple-system,system-ui,sans-serif",
      "background:#8a5200", "color:#fff", "box-shadow:0 2px 8px rgba(0,0,0,.35)",
    ].join(";"),
  );

  const text = document.createElement("span");
  text.style.flex = "1";
  text.textContent = verdict.reason ?? FALLBACK_REASON;

  const close = document.createElement("button");
  close.textContent = "Ignorer";
  close.setAttribute(
    "style",
    "background:transparent;border:1px solid #fff;color:#fff;border-radius:6px;padding:4px 10px;font:13px -apple-system,system-ui,sans-serif",
  );
  close.addEventListener("click", removeHost);

  bar.append(text, close);
  if (verdict.debug) {
    const dbg = debugLine(verdict.debug);
    dbg.style.marginTop = "6px";
    dbg.style.borderTop = "0";
    dbg.style.color = "#f0d0b0";
    bar.style.flexWrap = "wrap";
    bar.append(dbg);
  }
  shadow.append(bar);
}

/**
 * Full-screen interstitial. Blocks the page visually before any input, but
 * always offers "continuer quand même". Reached only on convergent evidence +
 * confirmed identity mismatch (PLAN.md §5).
 */
export function showInterstitial(verdict: Verdict): void {
  const shadow = ensureHost();
  if (!shadow) return;

  const overlay = document.createElement("div");
  overlay.setAttribute(
    "style",
    [
      "position:fixed", "inset:0", "z-index:2147483647",
      "display:flex", "align-items:flex-start", "justify-content:center",
      "padding:12vh 20px 20px", "box-sizing:border-box",
      "background:rgba(20,0,0,.94)", "backdrop-filter:blur(6px)",
      "font:17px -apple-system,system-ui,sans-serif", "color:#fff",
    ].join(";"),
  );

  const card = document.createElement("div");
  card.setAttribute(
    "style",
    "width:100%;max-width:560px;background:#1c1c1e;border:1px solid #5a1a1a;border-radius:22px;padding:28px 26px;box-shadow:0 16px 50px rgba(0,0,0,.55)",
  );

  const title = document.createElement("h1");
  title.setAttribute(
    "style",
    "margin:0 0 16px;font-size:26px;font-weight:700;line-height:1.2;display:flex;gap:10px;align-items:center",
  );
  title.textContent = "⚠️ Attention — page suspecte";

  const body = document.createElement("p");
  body.setAttribute("style", "margin:0 0 26px;font-size:19px;line-height:1.5;color:#e8e8ea");
  body.textContent = verdict.reason ?? FALLBACK_REASON;

  const leave = document.createElement("button");
  leave.textContent = "Quitter cette page";
  leave.setAttribute(
    "style",
    "width:100%;margin-bottom:12px;padding:17px;border:0;border-radius:14px;background:#ff453a;color:#fff;font-weight:600;font-size:19px",
  );
  leave.addEventListener("click", () => {
    // Best-effort: navigating away is safer than closing. history.back if we
    // can, else blank the page.
    if (window.history.length > 1) window.history.back();
    else window.location.replace("about:blank");
  });

  const proceed = document.createElement("button");
  proceed.textContent = "Continuer quand même";
  proceed.setAttribute(
    "style",
    "width:100%;padding:15px;border:0;border-radius:14px;background:transparent;color:#9a9a9e;font-size:17px;text-decoration:underline",
  );
  proceed.addEventListener("click", removeHost);

  card.append(title, body, leave, proceed);
  if (verdict.debug) card.append(debugLine(verdict.debug));
  overlay.append(card);
  shadow.append(overlay);
}

export function renderVerdict(verdict: Verdict): void {
  if (verdict.action === "interstitial") showInterstitial(verdict);
  else if (verdict.action === "banner") showBanner(verdict);
}
