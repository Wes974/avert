// Mirror of Shared/PageDossier.swift — keep both sides in sync.

export type CapturePointKind =
  | "password"
  | "payment-card"
  | "otp"
  | "seed-phrase"
  | "id-document-upload";

export interface CapturePoint {
  kind: CapturePointKind;
  visible: boolean;
  inIframe: boolean;
  /** Host of the form's action URL when it differs from the page host (L2 signal). */
  crossOriginActionHost: string | null;
}

import type { L1Signal } from "./l1";
import type { L2Signal } from "./l2";

export interface PageDossier {
  version: 1;
  url: string;
  host: string;
  /** Page title + visible-text excerpt, for L3 identity extraction only.
   *  Collected solely when L0 found a capture point; never persisted. */
  title: string;
  textExcerpt: string;
  capturePoints: CapturePoint[];
  l1Signals: L1Signal[];
  l2Signals: L2Signal[];
}

export type VerdictAction = "silent" | "banner" | "interstitial";

export interface Verdict {
  action: VerdictAction;
  score: number;
  reason: string | null;
  /** Echoed back by the native side so M0 can assert the round trip. */
  echoHost: string | null;
  /** Diagnostic string (L3 state, score breakdown). Shown small in the UI
   *  during bring-up; removed in M6. */
  debug?: string | null;
}

// Messages between content script and background.
export type ContentToBackground =
  | { type: "dossier"; dossier: PageDossier }
  | { type: "ack"; echoHost: string }
  // Content-script exceptions are invisible on iOS (no console); forward them
  // so the native handler can put them in the unified log.
  | { type: "jsError"; detail: string };

export type NativeResponse =
  | { type: "verdict"; verdict: Verdict }
  | { ok: true }
  | { error: string };

// Minimal typings for the Safari-provided `browser` global — only what we use.
declare global {
  const browser: {
    runtime: {
      sendMessage(message: ContentToBackground): Promise<NativeResponse>;
      sendNativeMessage(
        application: string,
        message: ContentToBackground,
      ): Promise<NativeResponse>;
      onMessage: {
        addListener(
          listener: (
            message: ContentToBackground,
            sender: unknown,
            sendResponse: (response: NativeResponse) => void,
          ) => boolean | void,
        ): void;
      };
    };
  };
}
