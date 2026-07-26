import Foundation

// Mirror of ts/src/types.ts — keep both sides in sync.

enum CapturePointKind: String, Codable, Sendable {
    case password
    case paymentCard = "payment-card"
    case otp
    case seedPhrase = "seed-phrase"
    case idDocumentUpload = "id-document-upload"
}

struct CapturePoint: Codable, Sendable {
    let kind: CapturePointKind
    let visible: Bool
    let inIframe: Bool
    /// Host of the form's action URL when it differs from the page host (L2 signal).
    let crossOriginActionHost: String?
}

struct L1Signal: Codable, Sendable {
    let id: String
    let detail: String?
    let brand: String?
}

struct L2Signal: Codable, Sendable {
    let id: String
    let detail: String?
    let brand: String?
}

struct PageDossier: Codable, Sendable {
    let version: Int
    let host: String
    /// For L3 identity extraction only; ephemeral, never persisted.
    let title: String
    let textExcerpt: String
    let capturePoints: [CapturePoint]
    let l1Signals: [L1Signal]
    let l2Signals: [L2Signal]
}

enum VerdictAction: String, Codable, Sendable {
    case silent
    case banner
    case interstitial
}

struct Verdict: Codable, Sendable {
    let action: VerdictAction
    let score: Int
    let reason: String?
    /// Echoed back so the JS side can assert the round trip in M0 tests.
    let echoHost: String?
    /// Whether to offer "ask someone you trust" on the interstitial. Decided
    /// here rather than in JS so the button never appears when it would do
    /// nothing. Cheap to compute: family mode is on iff a device label is set.
    var canAskForHelp: Bool = false
}
