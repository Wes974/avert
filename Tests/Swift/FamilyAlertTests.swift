import Foundation
import Testing
@testable import Avert

/// The family feature sends data off the device — the only thing in this app
/// that does. What may travel is therefore a contract, and these tests are how
/// it is held: the product decision ("the event, never the site") is asserted
/// mechanically, so widening it requires deleting a test rather than forgetting
/// a rule.
struct FamilyAlertTests {

    // MARK: - The privacy contract

    @Test("Le message envoyé ne porte QUE l'horodatage et le libellé d'appareil")
    func payloadIsExactlyTheAllowlist() {
        let alert = FamilyAlert(occurredAt: .now, deviceLabel: "iPhone de Papa")
        #expect(Set(alert.recordFields.keys) == FamilyAlert.recordKeys)
    }

    @Test("Aucun champ ne peut transporter une destination")
    func payloadCannotCarryADestination() {
        // Le cas qui compte : même si un hôte se retrouvait dans le libellé,
        // il n'y a aucune clé « host », « url », « brand » ou « domain » dans
        // laquelle il puisse voyager de façon structurée.
        let forbidden = ["host", "url", "brand", "domain", "site", "page", "link"]
        let keys = FamilyAlert.recordKeys.map { $0.lowercased() }
        for word in forbidden {
            #expect(!keys.contains { $0.contains(word) }, "clé interdite « \(word) » présente")
        }
    }

    @Test("Le libellé est tronqué : le champ ne doit pas devenir un canal")
    func labelCannotBecomeASmugglingChannel() {
        // Un libellé libre est nécessaire (« iPhone de Papa »), mais illimité il
        // deviendrait l'endroit où faire passer une URL.
        let long = String(repeating: "a", count: 500) + "https://paypal-verif.top/login"
        let alert = FamilyAlert(occurredAt: .now, deviceLabel: long)
        #expect(alert.deviceLabel.count == FamilyAlert.maxLabelLength)
        #expect(!alert.deviceLabel.contains("paypal"))
    }

    @Test("L'horodatage est arrondi à la seconde")
    func timestampIsCoarse() {
        // La précision sub-seconde n'apporte rien et offre une prise de
        // corrélation gratuite.
        let precise = Date(timeIntervalSince1970: 1_800_000_000.123456)
        let alert = FamilyAlert(occurredAt: precise, deviceLabel: "x")
        #expect(alert.occurredAt.timeIntervalSince1970 == 1_800_000_000)
    }

    @Test("Aller-retour : ce qui est encodé se relit à l'identique")
    func roundTrip() {
        let original = FamilyAlert(occurredAt: .now, deviceLabel: "iPad de Mamie")
        let restored = FamilyAlert(id: original.id, fields: original.recordFields)
        #expect(restored == original)
    }

    @Test("Un enregistrement corrompu ne produit pas d'alerte fantôme")
    func malformedRecordIsRejected() {
        #expect(FamilyAlert(id: UUID(), fields: [:]) == nil)
        #expect(FamilyAlert(id: UUID(), fields: ["occurredAt": "pas une date"]) == nil)
    }

    // MARK: - When an alert is warranted

    @Test("Seul un avertissement FORT et IGNORÉ déclenche une alerte")
    func onlyIgnoredStrongWarningsAlert() {
        #expect(FamilyAlertPolicy.shouldAlert(action: .interstitial, userContinued: true))
        // Averti et écouté : rien à signaler, le système a fonctionné.
        #expect(!FamilyAlertPolicy.shouldAlert(action: .interstitial, userContinued: false))
        // Un bandeau n'est pas un avertissement fort.
        #expect(!FamilyAlertPolicy.shouldAlert(action: .banner, userContinued: true))
        #expect(!FamilyAlertPolicy.shouldAlert(action: .silent, userContinued: true))
    }

    // MARK: - Link state

    @Test("Sans lien configuré, publier ne fait rien plutôt que d'échouer bruyamment")
    func publishingWithoutLink() async {
        let store = InMemoryFamilyStore(state: .off)
        await #expect(throws: FamilyError.notLinked) {
            try await store.publish(FamilyAlert(occurredAt: .now, deviceLabel: "x"))
        }
    }

    @Test("Le lien est actif seulement s'il reste au moins un proche")
    func activeRequiresAPeer() {
        #expect(!FamilyLinkState.off.isActive)
        #expect(!FamilyLinkState.linked(peers: []).isActive)
        #expect(!FamilyLinkState.unavailable(reason: "conteneur absent").isActive)
        #expect(FamilyLinkState.linked(peers: [
            FamilyPeer(id: "1", label: "Mamie", lastHeardFrom: nil, direction: .iWatchThem)
        ]).isActive)
    }

    @Test("Se délier efface aussi ce que cet appareil a publié")
    func unlinkErasesPublished() async throws {
        let peer = FamilyPeer(id: "1", label: "Papa", lastHeardFrom: nil, direction: .theyWatchMe)
        let store = InMemoryFamilyStore(state: .linked(peers: [peer]))
        try await store.publish(FamilyAlert(occurredAt: .now, deviceLabel: "moi"))
        #expect(await store.published.count == 1)

        try await store.unlinkAll()
        #expect(await store.currentState() == .off)
        #expect(await store.published.isEmpty)
    }

    @Test("Les alertes reçues sont rendues de la plus récente à la plus ancienne")
    func receivedAlertsAreOrdered() async throws {
        let old = FamilyAlert(occurredAt: Date(timeIntervalSince1970: 1000), deviceLabel: "a")
        let recent = FamilyAlert(occurredAt: Date(timeIntervalSince1970: 2000), deviceLabel: "b")
        let store = InMemoryFamilyStore(state: .off, received: [old, recent])
        let alerts = try await store.receivedAlerts(limit: 10)
        #expect(alerts.map(\.deviceLabel) == ["b", "a"])
    }
}
