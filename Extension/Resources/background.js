(()=>{browser.runtime.onMessage.addListener((n,r,e)=>{return browser.runtime.sendNativeMessage("application.id",n).then(e).catch((t)=>e({error:String(t)})),!0});})();
