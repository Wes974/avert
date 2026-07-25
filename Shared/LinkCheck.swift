import Foundation

/// Verdict for a bare link — no page, no DOM, no on-device model.
///
/// Deliberately *not* `ScoreEngine.evaluate` with a synthetic dossier. That
/// engine's thresholds are calibrated for a page that asks for a secret, with
/// DOM signals and an extracted identity to corroborate the URL. A link check
/// has one tenth of that evidence, so reusing those thresholds would either cry
/// wolf or say nothing. It gets its own three levels, and it never claims to
/// have seen the page — that honesty is the whole point of `LimitsView`.
struct LinkCheck: Sendable {
    enum Level: String, Sendable {
        /// The address imitates a registry brand it doesn't belong to.
        case impersonation
        /// Unusual traits, not conclusive on their own.
        case suspicious
        /// Nothing found *in the address*. Explicitly not "safe".
        case nothingFound
    }

    let level: Level
    let host: String
    let brand: String?
    let signals: [L1Signal]

    /// Signals that are themselves an identity claim contradicted by the domain.
    /// Same set as `ScoreEngine.identitySignalIds`, restricted to L1 (there is
    /// no DOM here).
    static let identitySignalIds: Set<String> = [
        "l1.homograph", "l1.typosquat", "l1.brand-subdomain",
    ]
}

enum LinkChecker {
    /// Nil when the input isn't an http(s) link at all (`mailto:`, plain text) —
    /// the caller shows "not a link" rather than a reassuring verdict.
    static func check(_ rawURL: String, brands: [BrandEntry]) -> LinkCheck? {
        guard let parsed = URLHeuristics.parse(rawURL) else { return nil }
        let signals = URLHeuristics.analyze(rawURL, brands: brands)

        let identity = signals.filter { LinkCheck.identitySignalIds.contains($0.id) && $0.brand != nil }
        let brand = identity.first?.brand
        let homograph = signals.contains { $0.id == "l1.homograph" }

        let level: LinkCheck.Level
        if !identity.isEmpty, homograph || signals.count >= 2 {
            // A homograph alone is enough: a Cyrillic character that folds onto a
            // brand name is not a coincidence. Anything else needs corroboration —
            // "amazonia.fr" is one edit away from "amazon" and entirely innocent,
            // and accusing it would be exactly the false positive that gets an
            // extension uninstalled.
            level = .impersonation
        } else if !signals.isEmpty {
            level = .suspicious
        } else {
            level = .nothingFound
        }

        return LinkCheck(level: level, host: parsed.host, brand: brand, signals: signals)
    }

    static func check(_ rawURL: String) -> LinkCheck? {
        check(rawURL, brands: BrandRegistry.shared.entries)
    }
}

// MARK: - Wording

extension LinkCheck {
    /// One line, the answer itself.
    var headline: String {
        switch level {
        case .impersonation:
            return String(format: String(localized: "link.headline.impersonation"), brand ?? "")
        case .suspicious:
            return String(localized: "link.headline.suspicious")
        case .nothingFound:
            return String(localized: "link.headline.nothing")
        }
    }

    /// Why — the user has to be able to judge for themselves (PLAN.md §6).
    var explanation: String {
        switch level {
        case .impersonation:
            return String(format: String(localized: "link.detail.impersonation"), brand ?? "", host)
        case .suspicious:
            return String(format: String(localized: "link.detail.suspicious"), host)
        case .nothingFound:
            return String(format: String(localized: "link.detail.nothing"), host)
        }
    }

    /// Never omitted, whatever the level: a link check reads the address only.
    /// Saying "nothing found" without this would be the false reassurance the
    /// whole product is built to avoid.
    var caveat: String {
        String(localized: "link.caveat")
    }

    /// Plain-language rendering of each signal, for the detail list.
    var findings: [String] {
        signals.compactMap { signal in
            let key = "link.signal.\(signal.id)"
            let template = String(localized: String.LocalizationValue(key))
            // An unresolved key returns the key itself; drop it rather than show
            // "link.signal.l1.foo" to a user.
            guard template != key else { return nil }
            return String(format: template, signal.brand ?? "", signal.detail ?? "")
        }
    }
}
