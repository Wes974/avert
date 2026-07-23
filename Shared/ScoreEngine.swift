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
        "l2.anti-inspection": 10,
        "l2.borrowed-brand-assets": 25,
    ]

    static let bannerThreshold = 40
    static let interstitialThreshold = 70

    /// `identityMismatch` is set by the identity comparison (registry, M3) or
    /// L3 extraction (M4): the page claims a brand whose domains don't match.
    func evaluate(_ dossier: PageDossier, identityMismatch: Bool = false) -> Verdict {
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
    private static func reason(
        contributing: [(id: String, weight: Int, brand: String?)],
        host: String
    ) -> String {
        let implicatedBrand = contributing.compactMap(\.brand).first
        let count = contributing.count
        if let brand = implicatedBrand {
            return "Cette page évoque « \(brand) » mais est hébergée sur \(host), qui n'appartient pas à cette marque (\(count) signaux convergents). Ne saisissez pas vos identifiants."
        }
        return "Cette page de connexion présente \(count) caractéristiques de page de phishing. Vérifiez l'adresse \(host) avant toute saisie."
    }
}
