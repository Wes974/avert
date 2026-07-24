import { GlobalRegistrator } from "@happy-dom/global-registrator";

// Registered exactly once per test process (module evaluation is cached), so
// multiple test files can share one happy-dom global without double-register.
if (typeof document === "undefined") {
  GlobalRegistrator.register({ url: "https://test.example/" });
}
