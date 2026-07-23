// Background script: sole relay between content scripts and the native
// handler (sendNativeMessage is not available to content scripts in Safari).
// Safari ignores the application id argument.

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  browser.runtime
    .sendNativeMessage("application.id", message)
    .then(sendResponse)
    .catch((err: unknown) => sendResponse({ error: String(err) }));
  return true; // async response
});
