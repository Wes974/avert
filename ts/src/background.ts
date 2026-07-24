// Background script: sole relay between content scripts and the native
// handler (sendNativeMessage is not available to content scripts in Safari).
// Safari ignores the application id argument.
//
// It also relays subframe → top-frame reports (frames.ts): going through the
// background keeps the exchange inside the extension, where the page can't
// observe it. `window.parent.postMessage` would have been simpler and would
// have handed any page a way to detect that Avert is installed.

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "frameCapture") {
    const tabId = sender.tab?.id;
    // frameId 0 is the top frame — the only one that decides and shows UI.
    if (tabId !== undefined && sender.frameId !== 0) {
      void browser.tabs.sendMessage(tabId, message, { frameId: 0 }).catch(() => {
        // Top frame may have no listener yet (or already navigated away).
      });
    }
    sendResponse({ relayed: true });
    return false;
  }

  browser.runtime
    .sendNativeMessage("application.id", message)
    .then(sendResponse)
    .catch((err: unknown) => sendResponse({ error: String(err) }));
  return true; // async response
});
