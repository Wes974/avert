(() => {
  // src/l0.ts
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
    for (const input of root.querySelectorAll('input[type="password"]')) {
      points.push({
        kind: "password",
        visible: isVisible(input),
        inIframe: window.self !== window.top,
        crossOriginActionHost: crossOriginActionHost(input)
      });
    }
    return points;
  }

  // src/content.ts
  async function run() {
    const capturePoints = detectCapturePoints(document);
    if (capturePoints.length === 0)
      return;
    const dossier = {
      version: 1,
      url: window.location.href,
      host: window.location.host,
      capturePoints
    };
    const response = await browser.runtime.sendMessage({
      type: "dossier",
      dossier
    });
    if ("type" in response && response.type === "verdict") {
      document.documentElement.dataset["impostor"] = response.verdict.action;
      await browser.runtime.sendMessage({
        type: "ack",
        echoHost: response.verdict.echoHost ?? ""
      });
    }
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => void run());
  } else {
    run();
  }
})();
