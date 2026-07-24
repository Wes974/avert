import type { Verdict } from "./types";

// Alert UI (PLAN.md §6): discreet banner for the 40–70 band, full-screen
// interstitial above 70 with confirmed identity mismatch. Both live in a
// closed shadow DOM so page CSS can't restyle or hide them, both always keep an
// escape hatch — an extension that blocks with no recourse gets uninstalled.
//
// Craft requirements met here (review 2026-07-24): safe-area insets, light/dark
// via prefers-color-scheme, relative units so Safari text-size scaling works,
// full VoiceOver semantics (role + aria-live + focus trap + focus return),
// reduced-motion-aware entrances, and proportional friction on the
// interstitial's "continue anyway" so it can't be dismissed by a reflex tap.

const HOST_ID = "impostor-ui-host";

const STYLE = `
  :host { all: initial; }
  * { box-sizing: border-box; }
  .imp-root {
    --bg-banner: #8a5200; --fg-banner: #fff;
    --overlay: rgba(18,16,22,.94);
    --card: #1c1b22; --card-line: #38333f; --fg: #f4f3f7; --fg-dim: #b9b7c4;
    --leave-bg: #4340c4; --leave-fg: #fff; --proceed: #9a99a8;
    --danger: #ff5a5f;
    font-family: -apple-system, system-ui, "SF Pro Text", sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  @media (prefers-color-scheme: light) {
    .imp-root {
      --bg-banner: #b8791b; --fg-banner: #1a1205;
      --overlay: rgba(40,36,48,.55);
      --card: #ffffff; --card-line: #e6e3ee; --fg: #1a1922; --fg-dim: #605f70;
      --leave-bg: #4340c4; --leave-fg: #fff; --proceed: #86859a; --danger: #d93a3f;
    }
  }

  .imp-banner {
    position: fixed; top: 0; left: 0; right: 0; z-index: 2147483647;
    display: flex; align-items: center; gap: .6rem;
    padding: calc(.7rem + env(safe-area-inset-top)) calc(.9rem + env(safe-area-inset-right)) .7rem calc(.9rem + env(safe-area-inset-left));
    background: var(--bg-banner); color: var(--fg-banner);
    box-shadow: 0 2px 12px rgba(0,0,0,.28); font-size: .95rem; line-height: 1.35;
  }
  .imp-banner .glyph { flex: 0 0 auto; width: 1.25rem; height: 1.25rem; }
  .imp-banner .msg { flex: 1 1 auto; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
  .imp-btn-dismiss {
    flex: 0 0 auto; min-height: 44px; min-width: 44px; padding: 0 .8rem;
    background: rgba(255,255,255,.14); border: 1px solid currentColor; color: inherit;
    border-radius: 10px; font: inherit; font-weight: 600; cursor: pointer;
  }

  .imp-overlay {
    position: fixed; inset: 0; z-index: 2147483647;
    display: flex; align-items: flex-start; justify-content: center;
    padding: calc(env(safe-area-inset-top) + 8vh) calc(1.25rem + env(safe-area-inset-right)) calc(env(safe-area-inset-bottom) + 1.25rem) calc(1.25rem + env(safe-area-inset-left));
    background: var(--overlay); -webkit-backdrop-filter: blur(7px); backdrop-filter: blur(7px);
  }
  .imp-card {
    width: 100%; max-width: 33rem; background: var(--card); color: var(--fg);
    border: 1px solid var(--card-line); border-radius: 22px; padding: 1.6rem 1.5rem;
    box-shadow: 0 18px 54px rgba(0,0,0,.5);
  }
  .imp-card h1 {
    margin: 0 0 .7rem; font-size: 1.5rem; font-weight: 700; line-height: 1.18;
    letter-spacing: -.01em; display: flex; align-items: center; gap: .55rem;
  }
  .imp-card h1 .glyph { width: 1.5rem; height: 1.5rem; flex: 0 0 auto; color: var(--danger); }
  .imp-card .msg { margin: 0 0 1.4rem; font-size: 1.12rem; line-height: 1.5; color: var(--fg-dim); }
  .imp-card .msg .host { font-family: ui-monospace, "SF Mono", Menlo, monospace; color: var(--fg); overflow-wrap: anywhere; }
  .imp-btn {
    display: flex; align-items: center; justify-content: center;
    width: 100%; min-height: 52px; padding: .9rem; border: 0; border-radius: 14px;
    font: inherit; font-size: 1.12rem; font-weight: 600; cursor: pointer; position: relative;
  }
  .imp-leave { background: var(--leave-bg); color: var(--leave-fg); margin-bottom: .6rem; }
  .imp-proceed {
    background: transparent; color: var(--proceed); font-size: 1rem; font-weight: 500;
    min-height: 48px; overflow: hidden;
  }
  .imp-proceed .fill { position: absolute; inset: 0; background: rgba(150,150,160,.16); width: 0%; }
  .imp-proceed .lbl { position: relative; text-decoration: underline; }
  .imp-hint { margin: .1rem 0 0; text-align: center; font-size: .8rem; color: var(--proceed); }

  .imp-dbg { margin-top: 1rem; padding-top: .7rem; border-top: 1px solid var(--card-line); font: .72rem ui-monospace, monospace; color: var(--proceed); overflow-wrap: anywhere; }

  button:focus-visible { outline: 3px solid #7d7bff; outline-offset: 2px; }

  @media (prefers-reduced-motion: no-preference) {
    .imp-banner { animation: imp-slide .22s cubic-bezier(.2,.7,.2,1) both; }
    .imp-overlay { animation: imp-fade .2s ease both; }
    .imp-card { animation: imp-rise .24s cubic-bezier(.2,.7,.2,1) both; }
    @keyframes imp-slide { from { transform: translateY(-100%); } to { transform: none; } }
    @keyframes imp-fade { from { opacity: 0; } to { opacity: 1; } }
    @keyframes imp-rise { from { opacity: 0; transform: translateY(14px) scale(.98); } to { opacity: 1; transform: none; } }
  }
`;

const ALERT_GLYPH =
  '<svg class="glyph" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3.2 1.8 20.5h20.4L12 3.2Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M12 9.5v5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="12" cy="17.6" r="1.15" fill="currentColor"/></svg>';

const FALLBACK_REASON =
  "Cette page présente plusieurs caractéristiques de page de phishing. Vérifiez l'adresse avant de saisir quoi que ce soit.";

let lastFocused: Element | null = null;

function ensureHost(): { root: HTMLElement; shadow: ShadowRoot } | null {
  if (document.getElementById(HOST_ID)) return null;
  lastFocused = document.activeElement;
  const host = document.createElement("div");
  host.id = HOST_ID;
  const shadow = host.attachShadow({ mode: "closed" });
  const style = document.createElement("style");
  style.textContent = STYLE;
  const root = document.createElement("div");
  root.className = "imp-root";
  shadow.append(style, root);
  document.documentElement.append(host);
  return { root, shadow };
}

function removeHost(): void {
  document.getElementById(HOST_ID)?.remove();
  // Return focus where the user was, so VoiceOver/keyboard don't get stranded.
  if (lastFocused instanceof HTMLElement) lastFocused.focus({ preventScroll: true });
  lastFocused = null;
}

// Keep Tab focus inside the card while it's up (modal semantics).
function trapFocus(container: HTMLElement): (e: KeyboardEvent) => void {
  return (e: KeyboardEvent) => {
    if (e.key !== "Tab") return;
    const items = [...container.querySelectorAll<HTMLElement>("button")];
    if (items.length === 0) return;
    const first = items[0];
    const last = items[items.length - 1];
    const active = container.getRootNode() instanceof ShadowRoot
      ? (container.getRootNode() as ShadowRoot).activeElement
      : document.activeElement;
    if (e.shiftKey && active === first) { e.preventDefault(); last?.focus(); }
    else if (!e.shiftKey && active === last) { e.preventDefault(); first?.focus(); }
  };
}

function debugEl(text: string): HTMLElement {
  const el = document.createElement("div");
  el.className = "imp-dbg";
  el.textContent = text;
  return el;
}

export function showBanner(verdict: Verdict): void {
  const h = ensureHost();
  if (!h) return;

  const bar = document.createElement("div");
  bar.className = "imp-banner";
  bar.setAttribute("role", "alert"); // announced automatically by VoiceOver

  const glyph = document.createElement("span");
  glyph.innerHTML = ALERT_GLYPH;

  const msg = document.createElement("span");
  msg.className = "msg";
  msg.textContent = verdict.reason ?? FALLBACK_REASON;

  const dismiss = document.createElement("button");
  dismiss.className = "imp-btn-dismiss";
  dismiss.type = "button";
  dismiss.textContent = "Ignorer";
  dismiss.setAttribute("aria-label", "Ignorer l’avertissement");
  dismiss.addEventListener("click", removeHost);

  bar.append(glyph, msg, dismiss);
  if (verdict.debug) bar.append(debugEl(verdict.debug));
  h.root.append(bar);
}

/**
 * Full-screen interstitial. Blocks the page visually before any input, but
 * always offers "continuer quand même" — behind a deliberate long-press so a
 * reflex tap can't bypass the strongest verdict.
 */
export function showInterstitial(verdict: Verdict): void {
  const h = ensureHost();
  if (!h) return;

  const overlay = document.createElement("div");
  overlay.className = "imp-overlay";

  const card = document.createElement("div");
  card.className = "imp-card";
  card.setAttribute("role", "alertdialog");
  card.setAttribute("aria-modal", "true");
  card.setAttribute("aria-labelledby", "imp-title");
  card.setAttribute("aria-describedby", "imp-msg");

  const title = document.createElement("h1");
  title.id = "imp-title";
  title.innerHTML = `${ALERT_GLYPH}<span>Attention — page suspecte</span>`;

  const msg = document.createElement("p");
  msg.className = "msg";
  msg.id = "imp-msg";
  msg.textContent = verdict.reason ?? FALLBACK_REASON;

  const leave = document.createElement("button");
  leave.className = "imp-btn imp-leave";
  leave.type = "button";
  leave.textContent = "Quitter cette page";
  leave.addEventListener("click", leavePage);

  const proceed = document.createElement("button");
  proceed.className = "imp-btn imp-proceed";
  proceed.type = "button";
  proceed.setAttribute("aria-label", "Continuer quand même — maintenir appuyé");
  const fill = document.createElement("span");
  fill.className = "fill";
  const lbl = document.createElement("span");
  lbl.className = "lbl";
  lbl.textContent = "Continuer quand même";
  proceed.append(fill, lbl);
  attachLongPress(proceed, fill, lbl, removeHost);

  const hint = document.createElement("p");
  hint.className = "imp-hint";
  hint.textContent = "Maintenez appuyé pour continuer";

  card.append(title, msg, leave, proceed, hint);
  if (verdict.debug) card.append(debugEl(verdict.debug));
  overlay.append(card);
  h.root.append(overlay);

  // Move focus into the dialog; trap it; Escape leaves (the safe action).
  leave.focus({ preventScroll: true });
  const trap = trapFocus(card);
  card.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { e.preventDefault(); leavePage(); }
    else trap(e);
  });
}

function leavePage(): void {
  if (window.history.length > 1) window.history.back();
  else window.location.replace("about:blank");
}

// Hold-to-confirm: ~1.4 s press fills a bar, then fires. Reduced-motion users
// get a plain confirm() instead of a timed gesture. Releasing early cancels.
function attachLongPress(
  btn: HTMLElement,
  fill: HTMLElement,
  lbl: HTMLElement,
  done: () => void,
): void {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) {
    btn.addEventListener("click", () => {
      if (window.confirm("Continuer vers cette page malgré l’avertissement ?")) done();
    });
    return;
  }

  const HOLD = 1400;
  let raf = 0;
  let start = 0;
  const step = (t: number) => {
    if (!start) start = t;
    const pct = Math.min(100, ((t - start) / HOLD) * 100);
    fill.style.width = `${pct}%`;
    if (pct >= 100) { cancel(); done(); return; }
    raf = requestAnimationFrame(step);
  };
  const begin = (e: Event) => { e.preventDefault(); start = 0; raf = requestAnimationFrame(step); };
  const cancel = () => { if (raf) cancelAnimationFrame(raf); raf = 0; start = 0; fill.style.width = "0%"; };

  btn.addEventListener("pointerdown", begin);
  btn.addEventListener("pointerup", cancel);
  btn.addEventListener("pointerleave", cancel);
  btn.addEventListener("pointercancel", cancel);
  // Keyboard: hold Enter/Space is awkward; offer a confirm() fallback on click.
  btn.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter" || (e as KeyboardEvent).key === " ") {
      e.preventDefault();
      if (window.confirm("Continuer vers cette page malgré l’avertissement ?")) done();
    }
  });
  lbl.setAttribute("aria-hidden", "false");
}

export function renderVerdict(verdict: Verdict): void {
  if (verdict.action === "interstitial") showInterstitial(verdict);
  else if (verdict.action === "banner") showBanner(verdict);
}
