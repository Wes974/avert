import Testing
@testable import Avert

/// The link check answers with far less evidence than the in-page engine: no DOM,
/// no extracted identity, just an address. These tests pin the wording of that
/// weakness — what it may accuse, and what it must only wonder about.
struct LinkCheckTests {
    private let registry: [BrandEntry] = [
        BrandEntry(brand: "PayPal", aliases: [], domains: ["paypal.com"],
                   authDelegates: [], sector: "payment", region: ["GLOBAL"]),
        BrandEntry(brand: "Amazon", aliases: [], domains: ["amazon.fr"],
                   authDelegates: [], sector: "retail", region: ["GLOBAL"]),
        BrandEntry(brand: "Impôts", aliases: [], domains: ["impots.gouv.fr"],
                   authDelegates: ["franceconnect.gouv.fr"], sector: "gov", region: ["FR"]),
    ]

    private func check(_ url: String) -> LinkCheck? {
        LinkChecker.check(url, brands: registry)
    }

    @Test("Le domaine légitime d'une marque ne trouve rien")
    func legitimateDomain() {
        #expect(check("https://www.paypal.com/signin")?.level == .nothingFound)
        #expect(check("https://franceconnect.gouv.fr/")?.level == .nothingFound)
    }

    @Test("Un homographe seul suffit à accuser")
    func homographAloneIsEnough() {
        // Un caractère cyrillique qui se replie sur un nom de marque n'est pas une
        // coïncidence : pas besoin de corroboration.
        let v = check("https://pаypal.com/login")
        #expect(v?.level == .impersonation)
        #expect(v?.brand == "PayPal")
    }

    @Test("Un typosquat seul reste une interrogation, pas une accusation")
    func singleTyposquatIsOnlySuspicious() {
        // « impot.fr » est à une édition de « impots » et peut très bien être un
        // site d'information légitime. Un seul indice de distance d'édition n'est
        // pas une preuve : niveau « inhabituel », pas « usurpation ».
        let v = check("https://impot.fr/")
        #expect(v?.level == .suspicious)
        #expect(v?.signals.count == 1)
        #expect(v?.signals.first?.id == "l1.typosquat")
    }

    @Test("Un mot plus long qu'une marque ne déclenche rien du tout")
    func distantNeighbourIsSilent() {
        // « amazonia.fr » est à deux éditions de « amazon », et la distance
        // maximale est de 1 pour un jeton de moins de 8 caractères : silence
        // complet, pas même une interrogation. C'est ce plafond serré qui évite
        // le faux positif qui fait désinstaller l'app — le verrouiller ici.
        let v = check("https://amazonia.fr/")
        #expect(v?.level == .nothingFound)
        #expect(v?.signals.isEmpty == true)
    }

    @Test("Marque en sous-domaine + TLD douteux : deux signaux → accusation")
    func convergenceAccuses() {
        let v = check("https://paypal.com.securite-client.xyz/login")
        #expect(v?.level == .impersonation)
        #expect(v?.brand == "PayPal")
        #expect((v?.signals.count ?? 0) >= 2)
    }

    @Test("Sans schéma : c'est la forme qu'on colle depuis un SMS")
    func schemelessInputWorks() {
        // new URL() côté JS refuserait ; ici c'est le cas d'usage principal.
        #expect(check("paypal-verif.top/login")?.level != nil)
    }

    @Test("Le piège du userinfo ne trompe pas le verdict")
    func userinfoTrap() {
        // L'hôte réel est evil.top. Un parseur naïf lirait paypal.com et
        // classerait le lien comme légitime.
        let v = check("https://paypal.com@evil.top/login")
        #expect(v?.host == "evil.top")
        #expect(v?.level != .nothingFound)
    }

    @Test("Ce qui n'est pas un lien web ne reçoit pas de verdict")
    func notALink() {
        #expect(check("mailto:someone@paypal.com") == nil)
        #expect(check("javascript:alert(1)") == nil)
        #expect(check("bonjour tout le monde") == nil)
    }

    @Test("La mise en garde accompagne TOUS les verdicts, y compris « rien trouvé »")
    func caveatAlwaysPresent() {
        // Dire « rien trouvé » sans préciser qu'on n'a pas vu la page serait la
        // fausse réassurance que tout le produit refuse (PLAN §6).
        for url in ["https://www.paypal.com/", "https://amazonia.fr/", "https://pаypal.com/"] {
            let v = check(url)
            #expect(v != nil)
            #expect(!(v?.caveat.isEmpty ?? true))
        }
    }

    @Test("Chaque signal produit une explication en langage clair")
    func findingsAreReadable() {
        let v = check("https://paypal.com.securite-client.xyz/login")
        let findings = v?.findings ?? []
        #expect(findings.count == v?.signals.count)
        // Aucune clé de localisation non résolue ne doit fuir dans l'UI.
        #expect(!findings.contains { $0.hasPrefix("link.signal.") })
    }
}
