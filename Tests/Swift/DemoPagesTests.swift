import Testing
@testable import Avert

/// The published demo pages (docs/demo/) are the only way someone who is not us
/// can check that Avert works. `ts/tests/demo-pages.test.ts` pins the signals
/// those pages emit; this pins what the engine must then decide.
///
/// Split across the two languages because the pipeline is: the signals are found
/// in JavaScript, the verdict is reached in Swift. Testing one half would leave
/// the demo able to break in the other.
struct DemoPagesTests {
    private let engine = ScoreEngine()

    /// Fictional brand, added to the registry so an interstitial can be
    /// demonstrated publicly without a page impersonating a real company.
    /// `.example` is reserved by RFC 2606 and can never be registered.
    private let registry = BrandRegistry(entries: [
        BrandEntry(brand: "Banque Démo", aliases: [], domains: ["banque-demo.example"],
                   authDelegates: [], sector: "banking", region: ["FR"]),
    ])

    /// Where the pages are actually served from — not a domain "Banque Démo" owns,
    /// which is the whole basis of the mismatch.
    private let host = "wes974.github.io"

    private func dossier(l2 ids: [(String, String?)]) -> PageDossier {
        PageDossier(
            version: 1, host: host, title: "", textExcerpt: "",
            capturePoints: [
                CapturePoint(kind: .password, visible: true, inIframe: false,
                             crossOriginActionHost: "collect.invalid"),
                CapturePoint(kind: .password, visible: false, inIframe: false,
                             crossOriginActionHost: "collect.invalid"),
            ],
            l1Signals: [],
            l2Signals: ids.map { L2Signal(id: $0.0, detail: nil, brand: $0.1) }
        )
    }

    private static let page1: [(String, String?)] = [
        ("l2.cross-origin-form", nil),
        ("l2.hidden-capture-field", nil),
    ]
    private static let page2 = page1 + [("l2.brand-logo-copy", "Banque Démo")]

    @Test("Page 1 : bandeau, et hors d'atteinte de l'alerte forte")
    func page1RaisesABanner() {
        let d = dossier(l2: Self.page1)
        #expect(!ScoreEngine.signalIdentityMismatch(d))

        let verdict = engine.evaluate(d, identityMismatch: ScoreEngine.signalIdentityMismatch(d))
        #expect(verdict.action == .banner)
        #expect(verdict.score == 55)   // 25 + 30, aucun multiplicateur
    }

    @Test("Page 2 : le logo copié rend l'incohérence d'identité, donc l'écran plein")
    func page2RaisesAnInterstitial() {
        let d = dossier(l2: Self.page2)
        #expect(ScoreEngine.signalIdentityMismatch(d))

        let verdict = engine.evaluate(d, identityMismatch: true)
        #expect(verdict.action == .interstitial)
        #expect(verdict.score == 160)  // (25 + 30 + 25) × 2
        // Le nom de la marque doit apparaître : c'est ce qui rend le test lisible
        // pour quelqu'un qui ne connaît pas le projet.
        #expect(verdict.reason?.contains("Banque Démo") == true)
    }

    @Test("Sans reconnaissance du logo, la page 2 retombe sur un bandeau")
    func page2DegradesToBanner() {
        // Cette dégradation est le diagnostic à distance : un testeur qui voit un
        // bandeau au lieu de l'écran plein nous apprend que l'empreinte n'a pas
        // matché — et non que l'extension est morte.
        let verdict = engine.evaluate(dossier(l2: Self.page1))
        #expect(verdict.action == .banner)
    }

    @Test("L'hôte de démonstration n'appartient pas à la marque de démonstration")
    func demoHostIsNotOwnedByTheDemoBrand() {
        // Si un jour les pages déménageaient sur banque-demo.example, le signal
        // serait légitimement supprimé et la démo deviendrait muette.
        #expect(registry.owner(ofHost: host) == nil)
        #expect(registry.owner(ofHost: "banque-demo.example")?.brand == "Banque Démo")
    }
}
