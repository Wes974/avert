import Foundation

/// Cumulative scoring engine (PLAN.md §5).
///
/// Never all-or-nothing: weighted signals, an identity multiplier, and two
/// thresholds. A strong alert always requires convergence of several signals —
/// a single signal can never cross the banner threshold on its own weight.
struct ScoreEngine {
    /// Indicative weights from PLAN.md §5; the M6 corpus calibrates them.
    static let weights: [String: Int] = [
        "l1.homograph": 35,
        "l1.punycode": 15,
        "l1.mixed-script": 20,
        "l1.typosquat": 30,
        "l1.combosquat": 20,
        "l1.brand-subdomain": 25,
        "l1.ip-literal": 15,
        "l1.exotic-port": 10,
        "l1.subdomain-depth": 10,
        "l1.low-rep-tld": 5,
        "l2.cross-origin-form": 25,
        "l2.hidden-capture-field": 30,
        "l2.thirdparty-iframe": 10,
        // A secret typed into a foreign frame. Deliberately light: embedded
        // payment fields are legitimate and common, so this must never be
        // enough to alert by itself (see ts/src/frames.ts).
        "l2.capture-in-thirdparty-iframe": 15,
        "l2.anti-inspection": 10,
        "l2.borrowed-brand-assets": 25,
        // A brand's logo copied pixel-for-pixel onto a host it doesn't own. Same
        // weight as a hotlinked one: the claim is identical, only the delivery
        // differs — and a self-hosted copy is if anything more deliberate.
        "l2.brand-logo-copy": 25,
        "history.unseen-domain": 10,
    ]

    static let bannerThreshold = 40
    static let interstitialThreshold = 70
    /// Below this base score, L3 never wakes up (PLAN.md §3: cost control).
    static let l3WakeThreshold = 20

    /// Signals that implicate a brand by construction on a non-owned host:
    /// they are themselves an identity claim contradicted by the domain.
    static let identitySignalIds: Set<String> = [
        "l1.homograph", "l1.typosquat", "l1.brand-subdomain",
        "l2.borrowed-brand-assets", "l2.brand-logo-copy",
    ]

    static func signalIdentityMismatch(_ dossier: PageDossier) -> Bool {
        dossier.l1Signals.contains { $0.brand != nil && identitySignalIds.contains($0.id) }
            || dossier.l2Signals.contains { $0.brand != nil && identitySignalIds.contains($0.id) }
    }

    /// `identityMismatch` comes from the signal-based check above and/or the
    /// L3 claimed-brand vs registry comparison (M4). `l3` adds the model's
    /// content findings to the score.
    func evaluate(
        _ dossier: PageDossier,
        identityMismatch: Bool = false,
        l3: PageIdentityExtraction? = nil,
        unseenLoginDomain: Bool = false
    ) -> Verdict {
        var score = 0
        var contributing: [(id: String, weight: Int, brand: String?)] = []

        for signal in dossier.l1Signals {
            let w = Self.weights[signal.id] ?? 0
            score += w
            if w > 0 { contributing.append((signal.id, w, signal.brand)) }
        }
        for signal in dossier.l2Signals {
            let w = Self.weights[signal.id] ?? 0
            score += w
            if w > 0 { contributing.append((signal.id, w, signal.brand)) }
        }

        // Opt-in history signal (off by default): a credential form on a domain
        // the user has never logged into before is mildly suspicious.
        if unseenLoginDomain {
            let w = Self.weights["history.unseen-domain"] ?? 10
            score += w
            contributing.append(("history.unseen-domain", w, nil))
        }

        if let l3, identityMismatch, !l3.claimedBrand.isEmpty {
            contributing.append(("l3.identity-mismatch", 0, l3.claimedBrand))
        }

        if identityMismatch {
            score *= 2
        }

        // Convergence rule: a single signal never raises an alert, whatever
        // its weight (PLAN.md §5 « jamais d'alerte forte sur un signal unique »).
        let action: VerdictAction
        if contributing.count < 2 {
            action = .silent
        } else if score > Self.interstitialThreshold, identityMismatch {
            action = .interstitial
        } else if score >= Self.bannerThreshold {
            action = .banner
        } else {
            action = .silent
        }

        return Verdict(
            action: action,
            score: score,
            reason: action == .silent ? nil : Self.reason(contributing: contributing, host: dossier.host),
            echoHost: dossier.host
        )
    }

    /// Human-readable explanation — the user must be able to judge (PLAN.md §6).
    ///
    /// Localised through the String Catalog with explicit keys and positional
    /// format specifiers rather than interpolated literals: this text ships in
    /// the *extension* bundle, and a key that silently fails to resolve would
    /// leave the alert with no explanation at all.
    private static func reason(
        contributing: [(id: String, weight: Int, brand: String?)],
        host: String
    ) -> String {
        let count = contributing.count
        if let brand = contributing.compactMap(\.brand).first {
            return String(
                format: String(localized: "verdict.reason.brand-mismatch"),
                brand, host, count
            )
        }
        return String(
            format: String(localized: "verdict.reason.generic"),
            count, host
        )
    }
}
