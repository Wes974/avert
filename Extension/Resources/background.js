(() => {
  // src/background.ts
  browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    browser.runtime.sendNativeMessage("application.id", message).then(sendResponse).catch((err) => sendResponse({ error: String(err) }));
    return true;
  });
})();
