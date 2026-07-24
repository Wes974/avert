(() => {
  // src/l0.ts
  var PAYMENT_ATTR = /card.?n(um|o)|cardnumber|cvv|cvc|cryptogramme|num.?carte/i;
  var OTP_ATTR = /\botp\b|one.?time|2fa|mfa|totp|verification.?code|code.?secur/i;
  var SEED_ATTR = /seed|mnemonic|recovery.?phrase|secret.?phrase|phrase.?secr/i;
  var ID_DOC_ATTR = /passport|passeport|identity|id.?card|cni|kyc|driver|permis/i;
  function attrBlob(el) {
    return [
      el.getAttribute("name"),
      el.getAttribute("id"),
      el.getAttribute("placeholder"),
      el.getAttribute("aria-label"),
      el.getAttribute("autocomplete")
    ].filter(Boolean).join(" ");
  }
  function classifyInput(el) {
    const tag = el.tagName.toLowerCase();
    const type = (el.getAttribute("type") ?? "text").toLowerCase();
    const autocomplete = (el.getAttribute("autocomplete") ?? "").toLowerCase();
    const blob = attrBlob(el);
    if (tag === "input" && type === "password")
      return "password";
    if (autocomplete.startsWith("cc-"))
      return "payment-card";
    if (tag === "input" && PAYMENT_ATTR.test(blob))
      return "payment-card";
    if (autocomplete === "one-time-code")
      return "otp";
    if (tag === "input" && OTP_ATTR.test(blob)) {
      const maxLen = parseInt(el.getAttribute("maxlength") ?? "99", 10);
      const numeric = (el.getAttribute("inputmode") ?? "") === "numeric";
      if (numeric || maxLen <= 8)
        return "otp";
    }
    if ((tag === "textarea" || tag === "input") && SEED_ATTR.test(blob))
      return "seed-phrase";
    if (tag === "input" && type === "file" && ID_DOC_ATTR.test(blob))
      return "id-document-upload";
    return null;
  }
  function isVisible(el) {
    const style = window.getComputedStyle(el);
    if (style.display === "none" || style.visibility === "hidden")
      return false;
    if (parseFloat(style.opacity) === 0)
      return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  function crossOriginActionHost(el) {
    const form = el.closest("form");
    if (!form)
      return null;
    const action = form.getAttribute("action");
    if (!action)
      return null;
    try {
      const actionUrl = new URL(action, window.location.href);
      return actionUrl.host !== window.location.host ? actionUrl.host : null;
    } catch {
      return null;
    }
  }
  function detectCapturePoints(root) {
    const points = [];
    for (const el of root.querySelectorAll("input, textarea")) {
      const kind = classifyInput(el);
      if (!kind)
        continue;
      points.push({
        kind,
        visible: el instanceof HTMLElement ? isVisible(el) : true,
        inIframe: window.self !== window.top,
        crossOriginActionHost: crossOriginActionHost(el)
      });
    }
    return points;
  }

  // src/l1.ts
  var PUNY_BASE = 36;
  var PUNY_TMIN = 1;
  var PUNY_TMAX = 26;
  var PUNY_SKEW = 38;
  var PUNY_DAMP = 700;
  var PUNY_INITIAL_BIAS = 72;
  var PUNY_INITIAL_N = 128;
  function punyAdapt(delta, numPoints, firstTime) {
    delta = firstTime ? Math.floor(delta / PUNY_DAMP) : delta >> 1;
    delta += Math.floor(delta / numPoints);
    let k = 0;
    while (delta > (PUNY_BASE - PUNY_TMIN) * PUNY_TMAX >> 1) {
      delta = Math.floor(delta / (PUNY_BASE - PUNY_TMIN));
      k += PUNY_BASE;
    }
    return k + Math.floor((PUNY_BASE - PUNY_TMIN + 1) * delta / (delta + PUNY_SKEW));
  }
  function punycodeDecode(input) {
    const output = [];
    let n = PUNY_INITIAL_N;
    let i = 0;
    let bias = PUNY_INITIAL_BIAS;
    const lastDelim = input.lastIndexOf("-");
    if (lastDelim > 0) {
      for (const ch of input.slice(0, lastDelim)) {
        const cp = ch.codePointAt(0) ?? 0;
        if (cp >= 128)
          return null;
        output.push(cp);
      }
    }
    let idx = lastDelim > 0 ? lastDelim + 1 : 0;
    while (idx < input.length) {
      const oldi = i;
      let w = 1;
      for (let k = PUNY_BASE;; k += PUNY_BASE) {
        if (idx >= input.length)
          return null;
        const cp = input.codePointAt(idx++) ?? 0;
        const digit = cp >= 97 ? cp - 97 : cp >= 65 ? cp - 65 : cp >= 48 ? cp - 48 + 26 : -1;
        if (digit < 0 || digit >= PUNY_BASE)
          return null;
        i += digit * w;
        const t = k <= bias ? PUNY_TMIN : k >= bias + PUNY_TMAX ? PUNY_TMAX : k - bias;
        if (digit < t)
          break;
        w *= PUNY_BASE - t;
      }
      bias = punyAdapt(i - oldi, output.length + 1, oldi === 0);
      n += Math.floor(i / (output.length + 1));
      i %= output.length + 1;
      output.splice(i, 0, n);
      i++;
    }
    return String.fromCodePoint(...output);
  }
  var CYRILLIC = /[Ѐ-ӿ]/;
  var GREEK = /[Ͱ-Ͽ]/;
  var LATIN = /[a-z]/i;
  function hasMixedScript(label) {
    const scripts = [CYRILLIC.test(label), GREEK.test(label), LATIN.test(label)];
    return scripts.filter(Boolean).length > 1;
  }
  var CONFUSABLES = {
    "а": "a",
    "е": "e",
    "о": "o",
    "р": "p",
    "с": "c",
    "х": "x",
    "у": "y",
    "і": "i",
    "ѕ": "s",
    "ԁ": "d",
    "ј": "j",
    " һ": "h",
    "ԛ": "q",
    "ԝ": "w",
    "ο": "o",
    "α": "a",
    "ν": "v",
    "ι": "i",
    "κ": "k",
    "τ": "t",
    "υ": "u",
    "0": "o",
    "1": "l",
    "3": "e",
    "5": "s",
    "7": "t"
  };
  function normalizeConfusables(s) {
    let out = "";
    for (const ch of s)
      out += CONFUSABLES[ch] ?? ch;
    return out;
  }
  function levenshtein(a, b, max) {
    if (Math.abs(a.length - b.length) > max)
      return max + 1;
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1;i <= a.length; i++) {
      const cur = [i];
      let rowMin = i;
      for (let j = 1;j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        const v = Math.min((prev[j] ?? 0) + 1, (cur[j - 1] ?? 0) + 1, (prev[j - 1] ?? 0) + cost);
        cur.push(v);
        if (v < rowMin)
          rowMin = v;
      }
      if (rowMin > max)
        return max + 1;
      prev = cur;
    }
    return prev[b.length] ?? max + 1;
  }
  var TWO_LEVEL_SUFFIXES = new Set([
    "co.uk",
    "org.uk",
    "gov.uk",
    "ac.uk",
    "com.au",
    "net.au",
    "org.au",
    "com.br",
    "com.mx",
    "com.ar",
    "co.jp",
    "co.in",
    "co.nz",
    "com.tr",
    "com.cn",
    "com.hk",
    "com.sg",
    "co.za",
    "gouv.fr",
    "asso.fr",
    "com.es"
  ]);
  function registrableDomain(host) {
    const labels = host.toLowerCase().split(".");
    if (labels.length <= 2)
      return labels.join(".");
    const lastTwo = labels.slice(-2).join(".");
    const take = TWO_LEVEL_SUFFIXES.has(lastTwo) ? 3 : 2;
    return labels.slice(-take).join(".");
  }
  var LOW_REP_TLDS = new Set([
    "top",
    "xyz",
    "tk",
    "ml",
    "ga",
    "cf",
    "gq",
    "icu",
    "click",
    "link",
    "work",
    "rest",
    "fit",
    "loan",
    "men",
    "bid",
    "stream",
    "racing",
    "win",
    "party",
    "date",
    "faith",
    "review",
    "vip",
    "monster",
    "quest",
    "cyou"
  ]);
  var COMBO_KEYWORDS = [
    "secure",
    "verif",
    "verification",
    "login",
    "signin",
    "sign-in",
    "account",
    "support",
    "update",
    "confirm",
    "wallet",
    "service",
    "auth",
    "id",
    "assistance",
    "client",
    "portail",
    "espace"
  ];
  function brandTokens(brand) {
    const tokens = new Set;
    for (const d of brand.domains) {
      const sld = registrableDomain(d).split(".")[0];
      if (sld && sld.length >= 4)
        tokens.add(sld);
    }
    return [...tokens];
  }
  function isOwnedBy(host, brand) {
    const reg = registrableDomain(host);
    return brand.domains.some((d) => reg === registrableDomain(d)) || brand.auth_delegates.some((d) => {
      const clean = d.replace(/^\*\./, "");
      return reg === registrableDomain(clean) || host === clean;
    });
  }
  function analyzeUrl(rawUrl, brands) {
    const signals = [];
    let url;
    try {
      url = new URL(rawUrl);
    } catch {
      return signals;
    }
    if (url.protocol !== "http:" && url.protocol !== "https:")
      return signals;
    const host = url.hostname.toLowerCase();
    const labels = host.split(".");
    const reg = registrableDomain(host);
    const sld = reg.split(".")[0] ?? "";
    const tld = labels[labels.length - 1] ?? "";
    const owner = brands.find((b) => isOwnedBy(host, b));
    if (owner)
      return signals;
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.startsWith("[")) {
      signals.push({ id: "l1.ip-literal", detail: host });
    }
    if (url.port !== "" && url.port !== "80" && url.port !== "443") {
      signals.push({ id: "l1.exotic-port", detail: url.port });
    }
    if (labels.length >= 5) {
      signals.push({ id: "l1.subdomain-depth", detail: String(labels.length) });
    }
    if (LOW_REP_TLDS.has(tld)) {
      signals.push({ id: "l1.low-rep-tld", detail: tld });
    }
    const decodedLabels = labels.map((l) => l.startsWith("xn--") ? punycodeDecode(l.slice(4)) ?? l : l);
    const hadPunycode = labels.some((l) => l.startsWith("xn--"));
    if (hadPunycode) {
      signals.push({ id: "l1.punycode", detail: decodedLabels.join(".") });
    }
    const decodedHost = decodedLabels.join(".");
    if (decodedLabels.some(hasMixedScript)) {
      signals.push({ id: "l1.mixed-script", detail: decodedHost });
    }
    const normalizedSld = normalizeConfusables(registrableDomain(decodedHost).split(".")[0] ?? sld);
    for (const brand of brands) {
      for (const token of brandTokens(brand)) {
        if (normalizedSld === token && sld !== token) {
          signals.push({ id: "l1.homograph", detail: `${sld} → ${token}`, brand: brand.brand });
          continue;
        }
        const maxDist = token.length >= 8 ? 2 : 1;
        const dist = levenshtein(normalizedSld, token, maxDist);
        if (dist > 0 && dist <= maxDist) {
          signals.push({ id: "l1.typosquat", detail: `${sld} ≈ ${token}`, brand: brand.brand });
          continue;
        }
        if (normalizedSld !== token && normalizedSld.includes(token)) {
          const rest = normalizedSld.replace(token, "");
          const luring = COMBO_KEYWORDS.some((k) => normalizedSld.includes(k)) || rest.includes("-");
          if (luring) {
            signals.push({ id: "l1.combosquat", detail: sld, brand: brand.brand });
            continue;
          }
        }
        const subLabels = decodedLabels.slice(0, -reg.split(".").length);
        if (subLabels.some((l) => normalizeConfusables(l).includes(token))) {
          signals.push({ id: "l1.brand-subdomain", detail: host, brand: brand.brand });
        }
      }
    }
    const seen = new Set;
    return signals.filter((s) => {
      const key = `${s.id}|${s.brand ?? ""}`;
      if (seen.has(key))
        return false;
      seen.add(key);
      return true;
    });
  }

  // src/l2.ts
  function brandOwning(host, brands) {
    const reg = registrableDomain(host);
    return brands.find((b) => b.domains.some((d) => reg === registrableDomain(d)) || b.auth_delegates.some((d) => reg === registrableDomain(d.replace(/^\*\./, "")))) ?? null;
  }
  function analyzePage(doc, pageHost, capturePoints, brands) {
    const signals = [];
    const crossOrigin = capturePoints.find((p) => p.crossOriginActionHost);
    if (crossOrigin?.crossOriginActionHost) {
      signals.push({ id: "l2.cross-origin-form", detail: crossOrigin.crossOriginActionHost });
    }
    if (capturePoints.some((p) => !p.visible)) {
      signals.push({ id: "l2.hidden-capture-field" });
    }
    for (const iframe of doc.querySelectorAll("iframe[src]")) {
      try {
        const src = new URL(iframe.getAttribute("src") ?? "", `https://${pageHost}`);
        if (src.host && src.host !== pageHost && !brandOwning(src.host, brands)) {
          const w = parseInt(iframe.getAttribute("width") ?? "0", 10);
          const h = parseInt(iframe.getAttribute("height") ?? "0", 10);
          const rect = iframe instanceof HTMLElement ? iframe.getBoundingClientRect() : { width: w, height: h };
          if ((rect.width || w) >= 200 && (rect.height || h) >= 100) {
            signals.push({ id: "l2.thirdparty-iframe", detail: src.host });
            break;
          }
        }
      } catch {}
    }
    const body = doc.body;
    const antiInspection = [];
    if (doc.documentElement.getAttribute("oncontextmenu") || body?.getAttribute("oncontextmenu")) {
      antiInspection.push("contextmenu");
    }
    if (body?.getAttribute("onselectstart") || body?.getAttribute("oncopy")) {
      antiInspection.push("selection");
    }
    if (body && typeof window !== "undefined") {
      const style = window.getComputedStyle(body);
      if (style.userSelect === "none")
        antiInspection.push("user-select");
    }
    if (antiInspection.length > 0) {
      signals.push({ id: "l2.anti-inspection", detail: antiInspection.join(",") });
    }
    const assetHosts = new Set;
    for (const link of doc.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')) {
      const href = link.getAttribute("href");
      if (href) {
        try {
          assetHosts.add(new URL(href, `https://${pageHost}`).host);
        } catch {}
      }
    }
    let imgCount = 0;
    for (const img of doc.querySelectorAll("img[src]")) {
      if (imgCount++ >= 50)
        break;
      try {
        assetHosts.add(new URL(img.getAttribute("src") ?? "", `https://${pageHost}`).host);
      } catch {}
    }
    const pageOwner = brandOwning(pageHost, brands);
    for (const host of assetHosts) {
      if (host === pageHost)
        continue;
      const assetOwner = brandOwning(host, brands);
      if (assetOwner && assetOwner !== pageOwner) {
        signals.push({
          id: "l2.borrowed-brand-assets",
          detail: host,
          brand: assetOwner.brand
        });
        break;
      }
    }
    return signals;
  }

  // src/generated/brands.ts
  var BRANDS = [
    { brand: "La Banque Postale", aliases: ["Banque Postale", "LBP"], domains: ["labanquepostale.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "BNP Paribas", aliases: ["BNP", "Hello bank!", "Hello bank"], domains: ["bnpparibas.net", "bnpparibas.com", "hellobank.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "Société Générale", aliases: ["SocGen", "SG"], domains: ["societegenerale.fr", "particuliers.sg.fr", "sg.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "Crédit Agricole", aliases: ["CA"], domains: ["credit-agricole.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "Caisse d'Épargne", aliases: ["Caisse d'Epargne"], domains: ["caisse-epargne.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "Crédit Mutuel", aliases: ["CIC"], domains: ["creditmutuel.fr", "cic.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "BoursoBank", aliases: ["Boursorama", "Boursorama Banque"], domains: ["boursobank.com", "boursorama.com"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "LCL", aliases: ["Crédit Lyonnais"], domains: ["lcl.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "Fortuneo", aliases: [], domains: ["fortuneo.fr"], auth_delegates: [], sector: "banking", region: ["FR"] },
    { brand: "N26", aliases: [], domains: ["n26.com"], auth_delegates: [], sector: "banking", region: ["EU"] },
    { brand: "Revolut", aliases: [], domains: ["revolut.com"], auth_delegates: [], sector: "banking", region: ["EU"] },
    { brand: "PayPal", aliases: [], domains: ["paypal.com"], auth_delegates: [], sector: "payment", region: ["GLOBAL"] },
    { brand: "Apple", aliases: ["iCloud", "App Store", "Apple ID"], domains: ["apple.com", "icloud.com"], auth_delegates: [], sector: "tech", region: ["GLOBAL"] },
    { brand: "Google", aliases: ["Gmail", "YouTube"], domains: ["google.com", "google.fr", "gmail.com", "youtube.com"], auth_delegates: [], sector: "tech", region: ["GLOBAL"] },
    { brand: "Microsoft", aliases: ["Outlook", "Office 365", "OneDrive", "Xbox"], domains: ["microsoft.com", "outlook.com", "office.com"], auth_delegates: ["microsoftonline.com", "live.com"], sector: "tech", region: ["GLOBAL"] },
    { brand: "Amazon", aliases: ["Prime"], domains: ["amazon.fr", "amazon.com"], auth_delegates: [], sector: "ecommerce", region: ["GLOBAL"] },
    { brand: "Netflix", aliases: [], domains: ["netflix.com"], auth_delegates: [], sector: "streaming", region: ["GLOBAL"] },
    { brand: "Facebook", aliases: ["Meta"], domains: ["facebook.com", "fb.com"], auth_delegates: [], sector: "social", region: ["GLOBAL"] },
    { brand: "Instagram", aliases: [], domains: ["instagram.com"], auth_delegates: [], sector: "social", region: ["GLOBAL"] },
    { brand: "WhatsApp", aliases: [], domains: ["whatsapp.com"], auth_delegates: [], sector: "social", region: ["GLOBAL"] },
    { brand: "Orange", aliases: ["Sosh"], domains: ["orange.fr", "sosh.fr"], auth_delegates: [], sector: "telecom", region: ["FR"] },
    { brand: "SFR", aliases: ["RED by SFR"], domains: ["sfr.fr", "red-by-sfr.fr"], auth_delegates: [], sector: "telecom", region: ["FR"] },
    { brand: "Free", aliases: ["Freebox", "Free Mobile"], domains: ["free.fr"], auth_delegates: [], sector: "telecom", region: ["FR"] },
    { brand: "Bouygues Telecom", aliases: ["Bouygues", "B&You"], domains: ["bouyguestelecom.fr"], auth_delegates: [], sector: "telecom", region: ["FR"] },
    { brand: "Impôts", aliases: ["impots.gouv", "DGFiP", "Direction générale des Finances publiques"], domains: ["impots.gouv.fr"], auth_delegates: ["franceconnect.gouv.fr"], sector: "government", region: ["FR"] },
    { brand: "Ameli", aliases: ["Assurance Maladie", "CPAM"], domains: ["ameli.fr"], auth_delegates: ["franceconnect.gouv.fr"], sector: "government", region: ["FR"] },
    { brand: "FranceConnect", aliases: [], domains: ["franceconnect.gouv.fr"], auth_delegates: [], sector: "government", region: ["FR"] },
    { brand: "La Poste", aliases: ["Colissimo"], domains: ["laposte.fr", "colissimo.fr"], auth_delegates: [], sector: "logistics", region: ["FR"] },
    { brand: "Chronopost", aliases: [], domains: ["chronopost.fr"], auth_delegates: [], sector: "logistics", region: ["FR"] },
    { brand: "DHL", aliases: [], domains: ["dhl.com", "dhl.fr"], auth_delegates: [], sector: "logistics", region: ["GLOBAL"] },
    { brand: "Binance", aliases: [], domains: ["binance.com"], auth_delegates: [], sector: "crypto", region: ["GLOBAL"] },
    { brand: "Coinbase", aliases: [], domains: ["coinbase.com"], auth_delegates: [], sector: "crypto", region: ["GLOBAL"] },
    { brand: "Ledger", aliases: ["Ledger Live"], domains: ["ledger.com"], auth_delegates: [], sector: "crypto", region: ["GLOBAL"] },
    { brand: "MetaMask", aliases: [], domains: ["metamask.io"], auth_delegates: [], sector: "crypto", region: ["GLOBAL"] }
  ];

  // src/banner.ts
  var HOST_ID = "impostor-ui-host";
  function ensureHost() {
    if (document.getElementById(HOST_ID))
      return null;
    const host = document.createElement("div");
    host.id = HOST_ID;
    const shadow = host.attachShadow({ mode: "closed" });
    document.documentElement.append(host);
    return shadow;
  }
  function removeHost() {
    document.getElementById(HOST_ID)?.remove();
  }
  var FALLBACK_REASON = "Cette page présente plusieurs caractéristiques de page de phishing. Vérifiez l'adresse avant de saisir quoi que ce soit.";
  function debugLine(text) {
    const el = document.createElement("div");
    el.setAttribute("style", "margin-top:16px;padding-top:12px;border-top:1px solid #333;font:12px ui-monospace,monospace;color:#7a7a7e;word-break:break-word");
    el.textContent = text;
    return el;
  }
  function showBanner(verdict) {
    const shadow = ensureHost();
    if (!shadow)
      return;
    const bar = document.createElement("div");
    bar.setAttribute("style", [
      "position:fixed",
      "top:0",
      "left:0",
      "right:0",
      "z-index:2147483647",
      "display:flex",
      "align-items:center",
      "gap:8px",
      "padding:10px 14px",
      "font:14px -apple-system,system-ui,sans-serif",
      "background:#8a5200",
      "color:#fff",
      "box-shadow:0 2px 8px rgba(0,0,0,.35)"
    ].join(";"));
    const text = document.createElement("span");
    text.style.flex = "1";
    text.textContent = verdict.reason ?? FALLBACK_REASON;
    const close = document.createElement("button");
    close.textContent = "Ignorer";
    close.setAttribute("style", "background:transparent;border:1px solid #fff;color:#fff;border-radius:6px;padding:4px 10px;font:13px -apple-system,system-ui,sans-serif");
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
  function showInterstitial(verdict) {
    const shadow = ensureHost();
    if (!shadow)
      return;
    const overlay = document.createElement("div");
    overlay.setAttribute("style", [
      "position:fixed",
      "inset:0",
      "z-index:2147483647",
      "display:flex",
      "align-items:flex-start",
      "justify-content:center",
      "padding:12vh 20px 20px",
      "box-sizing:border-box",
      "background:rgba(20,0,0,.94)",
      "backdrop-filter:blur(6px)",
      "font:17px -apple-system,system-ui,sans-serif",
      "color:#fff"
    ].join(";"));
    const card = document.createElement("div");
    card.setAttribute("style", "width:100%;max-width:560px;background:#1c1c1e;border:1px solid #5a1a1a;border-radius:22px;padding:28px 26px;box-shadow:0 16px 50px rgba(0,0,0,.55)");
    const title = document.createElement("h1");
    title.setAttribute("style", "margin:0 0 16px;font-size:26px;font-weight:700;line-height:1.2;display:flex;gap:10px;align-items:center");
    title.textContent = "⚠️ Attention — page suspecte";
    const body = document.createElement("p");
    body.setAttribute("style", "margin:0 0 26px;font-size:19px;line-height:1.5;color:#e8e8ea");
    body.textContent = verdict.reason ?? FALLBACK_REASON;
    const leave = document.createElement("button");
    leave.textContent = "Quitter cette page";
    leave.setAttribute("style", "width:100%;margin-bottom:12px;padding:17px;border:0;border-radius:14px;background:#ff453a;color:#fff;font-weight:600;font-size:19px");
    leave.addEventListener("click", () => {
      if (window.history.length > 1)
        window.history.back();
      else
        window.location.replace("about:blank");
    });
    const proceed = document.createElement("button");
    proceed.textContent = "Continuer quand même";
    proceed.setAttribute("style", "width:100%;padding:15px;border:0;border-radius:14px;background:transparent;color:#9a9a9e;font-size:17px;text-decoration:underline");
    proceed.addEventListener("click", removeHost);
    card.append(title, body, leave, proceed);
    if (verdict.debug)
      card.append(debugLine(verdict.debug));
    overlay.append(card);
    shadow.append(overlay);
  }
  function renderVerdict(verdict) {
    if (verdict.action === "interstitial")
      showInterstitial(verdict);
    else if (verdict.action === "banner")
      showBanner(verdict);
  }

  // src/content.ts
  function identityCues() {
    const parts = [];
    const push = (s) => {
      const t = (s ?? "").trim();
      if (t && t.length <= 80)
        parts.push(t);
    };
    push(document.querySelector('meta[property="og:site_name"]')?.getAttribute("content"));
    push(document.querySelector('meta[name="application-name"]')?.getAttribute("content"));
    for (const img of document.querySelectorAll("img[alt]")) {
      const alt = img.getAttribute("alt") ?? "";
      if (/logo|brand/i.test(img.getAttribute("class") ?? "") || /logo/i.test(alt))
        push(alt);
    }
    let headings = 0;
    for (const h of document.querySelectorAll("h1, h2, h3, legend")) {
      push(h.textContent);
      if (++headings >= 4)
        break;
    }
    return [...new Set(parts)].join(" · ").slice(0, 400);
  }
  async function run() {
    const capturePoints = detectCapturePoints(document);
    if (capturePoints.length === 0)
      return;
    const dossier = {
      version: 1,
      url: window.location.href,
      host: window.location.host,
      title: document.title.slice(0, 200),
      textExcerpt: identityCues(),
      capturePoints,
      l1Signals: analyzeUrl(window.location.href, BRANDS),
      l2Signals: analyzePage(document, window.location.host, capturePoints, BRANDS)
    };
    const response = await browser.runtime.sendMessage({
      type: "dossier",
      dossier
    });
    if ("type" in response && response.type === "verdict") {
      document.documentElement.dataset["impostor"] = response.verdict.action;
      renderVerdict(response.verdict);
      await browser.runtime.sendMessage({
        type: "ack",
        echoHost: response.verdict.echoHost ?? ""
      });
    }
  }
  function runReporting() {
    run().catch((err) => {
      browser.runtime.sendMessage({
        type: "jsError",
        detail: err instanceof Error ? `${err.name}: ${err.message}` : String(err)
      });
    });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runReporting);
  } else {
    runReporting();
  }
})();
