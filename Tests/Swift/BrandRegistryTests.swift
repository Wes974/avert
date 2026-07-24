import Testing
@testable import Avert

/// Identity comparison is the load-bearing factual step (LLM extracts, Swift
/// decides). Test with an injected registry — never `.shared`, which reads the
/// bundle and would be empty in the test runner.
struct BrandRegistryTests {
    private let registry = BrandRegistry(entries: [
        BrandEntry(brand: "La Banque Postale", aliases: ["Banque Postale", "LBP"],
                   domains: ["labanquepostale.fr"], authDelegates: ["*.wl-fr.com"],
                   sector: "banking", region: ["FR"]),
        BrandEntry(brand: "PayPal", aliases: [], domains: ["paypal.com"],
                   authDelegates: [], sector: "payment", region: ["GLOBAL"]),
        BrandEntry(brand: "Impôts", aliases: ["impots.gouv"], domains: ["impots.gouv.fr"],
                   authDelegates: ["franceconnect.gouv.fr"], sector: "gov", region: ["FR"]),
    ])

    @Test("registrableDomain gère les suffixes à deux niveaux")
    func registrable() {
        #expect(BrandRegistry.registrableDomain("accounts.google.com") == "google.com")
        #expect(BrandRegistry.registrableDomain("impots.gouv.fr") == "impots.gouv.fr")
        #expect(BrandRegistry.registrableDomain("a.b.evil.co.uk") == "evil.co.uk")
        #expect(BrandRegistry.registrableDomain("host.example.com:8443") == "example.com")
    }

    @Test("owns : domaines et délégués d'auth (wildcard)")
    func ownership() {
        let lbp = registry.entries[0]
        #expect(registry.owns(host: "labanquepostale.fr", brand: lbp))
        #expect(registry.owns(host: "www.labanquepostale.fr", brand: lbp))
        #expect(registry.owns(host: "auth.wl-fr.com", brand: lbp))       // délégué
        #expect(!registry.owns(host: "lbp-secure.top", brand: lbp))
    }

    @Test("Matching de marque : insensible à la casse et aux diacritiques, + alias")
    func matching() {
        #expect(registry.match(claimedBrand: "paypal")?.brand == "PayPal")
        #expect(registry.match(claimedBrand: "IMPÔTS")?.brand == "Impôts")
        #expect(registry.match(claimedBrand: "impots")?.brand == "Impôts")     // sans accent
        #expect(registry.match(claimedBrand: "LBP")?.brand == "La Banque Postale") // alias
        #expect(registry.match(claimedBrand: "Netflix") == nil)
    }

    @Test("identityMismatch : le cœur du verdict")
    func mismatch() {
        // Marque revendiquée mais mauvais domaine → mismatch.
        #expect(registry.identityMismatch(claimedBrand: "PayPal", host: "lbp-secure-verif.top"))
        // Marque revendiquée sur son vrai domaine → pas de mismatch.
        #expect(!registry.identityMismatch(claimedBrand: "PayPal", host: "www.paypal.com"))
        // Marque sur un délégué d'auth légitime → pas de mismatch.
        #expect(!registry.identityMismatch(claimedBrand: "Impôts", host: "franceconnect.gouv.fr"))
        // Marque inconnue du registre → pas de verdict d'identité (false).
        #expect(!registry.identityMismatch(claimedBrand: "Inconnue", host: "n-importe-quoi.top"))
    }

    @Test("owner : retrouve la marque propriétaire d'un hôte")
    func owner() {
        #expect(registry.owner(ofHost: "paypal.com")?.brand == "PayPal")
        #expect(registry.owner(ofHost: "evil.top") == nil)
    }
}
