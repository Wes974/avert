import Testing
@testable import Avert

/// The decision core is pure and deterministic — these lock the non-negotiable
/// product rules (PLAN.md §5) so a scoring regression can't pass silently.
struct ScoreEngineTests {
    private let engine = ScoreEngine()

    private func dossier(
        host: String = "example.com",
        l1: [L1Signal] = [],
        l2: [L2Signal] = []
    ) -> PageDossier {
        PageDossier(
            version: 1, host: host, title: "", textExcerpt: "",
            capturePoints: [CapturePoint(kind: .password, visible: true, inIframe: false, crossOriginActionHost: nil)],
            l1Signals: l1, l2Signals: l2
        )
    }
    private func l1(_ id: String, brand: String? = nil) -> L1Signal { L1Signal(id: id, detail: nil, brand: brand) }
    private func l2(_ id: String, brand: String? = nil) -> L2Signal { L2Signal(id: id, detail: nil, brand: brand) }

    @Test("Silence par défaut : aucun signal → silent")
    func emptyIsSilent() {
        #expect(engine.evaluate(dossier()).action == .silent)
    }

    @Test("Convergence : un signal unique ne déclenche jamais d'alerte, quel que soit son poids")
    func singleSignalNeverAlerts() {
        // homograph = 35, mais seul → convergence non atteinte.
        let v = engine.evaluate(dossier(l1: [l1("l1.homograph")]))
        #expect(v.action == .silent)
    }

    @Test("Deux signaux convergents franchissant 40 → bandeau")
    func twoSignalsBanner() {
        // cross-origin-form 25 + hidden 30 = 55 ≥ 40, sans mismatch.
        let v = engine.evaluate(dossier(l2: [l2("l2.cross-origin-form"), l2("l2.hidden-capture-field")]))
        #expect(v.action == .banner)
        #expect(v.score == 55)
    }

    @Test("Multiplicateur d'identité ×2 sur incohérence confirmée")
    func identityMultiplier() {
        let d = dossier(l1: [l1("l1.typosquat", brand: "PayPal")], l2: [l2("l2.cross-origin-form")])
        let base = engine.evaluate(d)                                   // 30 + 25 = 55
        let withMismatch = engine.evaluate(d, identityMismatch: true)   // ×2 = 110
        #expect(withMismatch.score == base.score * 2)
    }

    @Test("Interstitiel : >70 ET incohérence d'identité")
    func interstitialNeedsMismatch() {
        let d = dossier(l1: [l1("l1.homograph", brand: "Apple")], l2: [l2("l2.borrowed-brand-assets", brand: "Apple")])
        // 35 + 25 = 60 ; sans mismatch → banner malgré 2 signaux.
        #expect(engine.evaluate(d).action == .banner)
        // avec mismatch → 120 > 70 → interstitiel.
        #expect(engine.evaluate(d, identityMismatch: true).action == .interstitial)
    }

    @Test("Un score >70 sans incohérence d'identité ne passe pas en interstitiel")
    func highScoreNoMismatchStaysBanner() {
        // Trois signaux lourds sans mismatch : score haut mais pas interstitiel.
        let d = dossier(l2: [l2("l2.hidden-capture-field"), l2("l2.cross-origin-form"), l2("l2.borrowed-brand-assets")])
        let v = engine.evaluate(d)
        #expect(v.score > 70)
        #expect(v.action == .banner)
    }

    @Test("Le signal 'domaine jamais vu' contribue à la convergence")
    func unseenDomainSignal() {
        // Un seul signal L1 (typosquat 30) → silent ; + unseen (10) = 2 signaux, 40 → banner.
        let d = dossier(l1: [l1("l1.typosquat", brand: "PayPal")])
        #expect(engine.evaluate(d).action == .silent)
        #expect(engine.evaluate(d, unseenLoginDomain: true).action == .banner)
    }

    @Test("Un secret saisi dans une iframe tierce ne suffit pas à alerter")
    func thirdPartyIframeCaptureIsNotEnough() {
        // Cas légitime le plus courant : champ de paiement embarqué (Stripe…).
        // 15 + 10 = 25 < 40 → silence, malgré deux signaux convergents.
        let d = dossier(l2: [l2("l2.capture-in-thirdparty-iframe"), l2("l2.thirdparty-iframe")])
        let v = engine.evaluate(d)
        #expect(v.score == 25)
        #expect(v.action == .silent)
    }

    @Test("La même iframe tierce sur un domaine usurpateur alerte")
    func thirdPartyIframeCaptureWithMismatch() {
        let d = dossier(
            l1: [l1("l1.typosquat", brand: "PayPal")],
            l2: [l2("l2.capture-in-thirdparty-iframe")]
        )
        // (30 + 15) × 2 = 90 > 70 avec incohérence d'identité → interstitiel.
        let v = engine.evaluate(d, identityMismatch: true)
        #expect(v.action == .interstitial)
    }

    @Test("Un verdict non-silencieux porte toujours une raison")
    func nonSilentHasReason() {
        let v = engine.evaluate(dossier(l2: [l2("l2.cross-origin-form"), l2("l2.hidden-capture-field")]))
        #expect(v.reason != nil && !(v.reason ?? "").isEmpty)
    }
}
