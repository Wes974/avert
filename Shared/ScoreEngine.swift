import Foundation
import os.log

/// Cumulative scoring engine (PLAN.md §5).
///
/// Never all-or-nothing: weighted signals, an identity multiplier, and two
/// thresholds. A strong alert always requires convergence of several signals —
/// a single signal can never cross the banner threshold on its own weight.
/// The calibration, as read from registry/scoring.json.
///
/// Its own type rather than loose constants: the values now come from a file,
/// so the decode can fail, and a silently-empty calibration would disable every
/// alert — the worst possible failure mode, and an invisible one.
struct ScoringPolicy: Codable, Sendable {
    let weights: [String: Int]
    let thresholds: Thresholds
    let identitySignals: Set<String>
    let identityMultiplier: Int
    let minimumConvergingSignals: Int

    struct Thresholds: Codable, Sendable {
        let banner: Int
        let interstitial: Int
        let l3Wake: Int
    }

    /// Compiled-in fallback, identical to the shipped file. Used only if the
    /// bundle resource is missing or malformed — the alternative is an engine
    /// that scores everything at zero and never warns anyone.
    static let fallback = ScoringPolicy(
        weights: [
            "l1.homograph": 35, "l1.punycode": 15, "l1.mixed-script": 20,
            "l1.typosquat": 30, "l1.combosquat": 20, "l1.brand-subdomain": 25,
            "l1.ip-literal": 15, "l1.exotic-port": 10, "l1.subdomain-depth": 10,
            "l1.low-rep-tld": 5, "l2.cross-origin-form": 25,
            "l2.hidden-capture-field": 30, "l2.thirdparty-iframe": 10,
            "l2.capture-in-thirdparty-iframe": 15, "l2.anti-inspection": 10,
            "l2.borrowed-brand-assets": 25, "l2.brand-logo-copy": 25,
            "history.unseen-domain": 10,
        ],
        thresholds: Thresholds(banner: 40, interstitial: 70, l3Wake: 20),
        identitySignals: [
            "l1.homograph", "l1.typosquat", "l1.brand-subdomain",
            "l2.borrowed-brand-assets", "l2.brand-logo-copy",
        ],
        identityMultiplier: 2,
        minimumConvergingSignals: 2
    )

    static let shared: ScoringPolicy = {
        guard let url = Bundle.main.url(forResource: "scoring", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(ScoringPolicy.self, from: data),
              !policy.weights.isEmpty
        else {
            Logger(subsystem: "com.ouweis.avert", category: "scoring")
                .fault("scoring.json missing or malformed — falling back to compiled defaults")
            assertionFailure("scoring.json failed to load")
            return fallback
        }
        return policy
    }()
}

struct ScoreEngine {
    /// Indicative weights (PLAN.md §5), now data rather than code — see
    /// registry/scoring.json. They stay indicative until the evaluation harness
    /// measures their effect on a real corpus: moving them here does not
    /// validate them, it makes them measurable.
    static var weights: [String: Int] { ScoringPolicy.shared.weights }

    static var bannerThreshold: Int { ScoringPolicy.shared.thresholds.banner }
    static var interstitialThreshold: Int { ScoringPolicy.shared.thresholds.interstitial }
    /// Below this base score, L3 never wakes up (PLAN.md §3: cost control).
    static var l3WakeThreshold: Int { ScoringPolicy.shared.thresholds.l3Wake }

    /// Signals that implicate a brand by construction on a non-owned host:
    /// they are themselves an identity claim contradicted by the domain.
    static var identitySignalIds: Set<String> { ScoringPolicy.shared.identitySignals }

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
            score *= ScoringPolicy.shared.identityMultiplier
        }

        // Convergence rule: a single signal never raises an alert, whatever
        // its weight (PLAN.md §5 « jamais d'alerte forte sur un signal unique »).
        let action: VerdictAction
        if contributing.count < ScoringPolicy.shared.minimumConvergingSignals {
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
