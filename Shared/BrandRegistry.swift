import Foundation
import os.log

/// Embedded brand registry (PLAN.md §4). Loaded once from the bundled
/// registry/brands.json — the same file the TS side compiles in. No runtime
/// fetch, ever.
struct BrandEntry: Codable, Sendable {
    let brand: String
    let aliases: [String]
    let domains: [String]
    let authDelegates: [String]
    let sector: String
    let region: [String]

    enum CodingKeys: String, CodingKey {
        case brand, aliases, domains, sector, region
        case authDelegates = "auth_delegates"
    }
}

struct BrandRegistry: Sendable {
    let entries: [BrandEntry]

    static let shared: BrandRegistry = {
        guard let url = Bundle.main.url(forResource: "brands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([BrandEntry].self, from: data),
              !entries.isEmpty
        else {
            // An empty registry silently disables every identity verdict — the
            // worst possible failure (no alert, no sign). Make it loud.
            Logger(subsystem: "com.ouweis.impostor", category: "registry")
                .fault("brands.json missing or empty from bundle — identity detection is OFF")
            assertionFailure("brands.json failed to load — identity detection disabled")
            return BrandRegistry(entries: [])
        }
        return BrandRegistry(entries: entries)
    }()

    /// Registrable domain, mirroring the TS approximation (common two-level
    /// public suffixes only).
    static let twoLevelSuffixes: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "net.au", "org.au",
        "com.br", "com.mx", "com.ar", "co.jp", "co.in", "co.nz", "com.tr",
        "com.cn", "com.hk", "com.sg", "co.za", "gouv.fr", "asso.fr", "com.es",
    ]

    static func registrableDomain(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ":").first
            .map(String.init)?.split(separator: ".").map(String.init) ?? []
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let take = twoLevelSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }

    /// Does this host belong to the brand (own domain or auth delegate)?
    func owns(host: String, brand: BrandEntry) -> Bool {
        let reg = Self.registrableDomain(host)
        if brand.domains.contains(where: { Self.registrableDomain($0) == reg }) { return true }
        return brand.authDelegates.contains { delegate in
            let clean = delegate.hasPrefix("*.") ? String(delegate.dropFirst(2)) : delegate
            return Self.registrableDomain(clean) == reg || host.lowercased() == clean
        }
    }

    func owner(ofHost host: String) -> BrandEntry? {
        entries.first { owns(host: host, brand: $0) }
    }

    /// Resolve a brand name claimed by page content (L3 output) against the
    /// registry: exact name or alias, case- and diacritic-insensitive.
    func match(claimedBrand: String) -> BrandEntry? {
        let normalized = Self.normalize(claimedBrand)
        guard !normalized.isEmpty else { return nil }
        return entries.first { entry in
            Self.normalize(entry.brand) == normalized
                || entry.aliases.contains { Self.normalize($0) == normalized }
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The core identity verdict (PLAN.md §3 L3): the page claims a brand →
    /// does the actual host belong to it (or one of its auth delegates)?
    func identityMismatch(claimedBrand: String, host: String) -> Bool {
        guard let entry = match(claimedBrand: claimedBrand) else { return false }
        return !owns(host: host, brand: entry)
    }
}
