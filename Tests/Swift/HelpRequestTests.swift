import Foundation
import Testing
@testable import Avert

/// `HelpRequest` sends the host on purpose, `FamilyAlert` can never send it.
/// Both are contracts, and both are held here — including the boundary between
/// them, so that a later edit cannot quietly turn the automatic feature into the
/// deliberate one.
struct HelpRequestTests {

    // MARK: - What separates the two features

    @Test("La demande d'aide porte l'hôte : c'est la question elle-même")
    func requestCarriesHost() {
        let r = HelpRequest(askedAt: .now, askerLabel: "Mamie", host: "paypal-verif.top")
        #expect(r.recordFields["host"] == "paypal-verif.top")
    }

    @Test("L'alerte automatique ne peut toujours pas porter d'hôte")
    func alertStillCannot() {
        // La frontière entre les deux fonctionnalités, asservie. Si un jour
        // FamilyAlert gagne un champ de destination, ce test tombe.
        #expect(!FamilyAlert.recordKeys.contains("host"))
        #expect(HelpRequest.recordKeys.contains("host"))
    }

    @Test("Seul l'hôte est envoyé, jamais le chemin ni la requête")
    func onlyHostEverTravels() {
        // Un chemin peut contenir un jeton de session ou un lien magique, et
        // n'aide personne à juger un domaine.
        let r = HelpRequest(
            askedAt: .now, askerLabel: "x",
            host: "https://user:pw@paypal-verif.top/login?token=SECRET#frag"
        )
        #expect(r.host == "paypal-verif.top")
        #expect(!r.host.contains("SECRET"))
        #expect(!r.host.contains("login"))
        #expect(!r.host.contains("user"))
    }

    @Test("Le piège du userinfo ne survit pas non plus ici")
    func userinfoStripped() {
        let r = HelpRequest(askedAt: .now, askerLabel: "x", host: "paypal.com@evil.top")
        #expect(r.host == "evil.top")
    }

    // MARK: - Expiry

    @Test("Une demande expire au bout de 24 h, répondue ou non")
    func expires() {
        let old = HelpRequest(askedAt: .now.addingTimeInterval(-25 * 3600), askerLabel: "x", host: "a.fr")
        let fresh = HelpRequest(askedAt: .now.addingTimeInterval(-3600), askerLabel: "x", host: "a.fr")
        #expect(old.isExpired())
        #expect(!fresh.isExpired())
    }

    @Test("L'expiration est courte : un historique serait le journal qu'on refuse")
    func expiryStaysShort() {
        #expect(HelpRequest.expiry <= 48 * 3600)
    }

    // MARK: - Answers

    @Test("« Je ne sais pas » est une réponse à part entière")
    func unsureIsAnAnswer() {
        // Un proche qui n'est pas sûr doit pouvoir le dire : un « c'est bon »
        // erroné est pire que pas de réponse du tout.
        #expect(HelpRequest.Answer.allCases.contains(.unsure))
        var r = HelpRequest(askedAt: .now, askerLabel: "x", host: "a.fr")
        #expect(!r.isAnswered)
        r.answer = .unsure
        #expect(r.isAnswered)
    }

    @Test("Aller-retour complet, réponse comprise")
    func roundTrip() {
        let original = HelpRequest(
            askedAt: .now, askerLabel: "Mamie", host: "paypal-verif.top",
            verdictSummary: "2 signaux convergents",
            answer: .dangerous, answeredAt: .now, answeredBy: "Papa"
        )
        let restored = HelpRequest(id: original.id, fields: original.recordFields)
        #expect(restored?.host == original.host)
        #expect(restored?.answer == .dangerous)
        #expect(restored?.answeredBy == "Papa")
    }

    @Test("Une demande sans hôte est rejetée : elle ne veut rien dire")
    func hostIsRequired() {
        #expect(HelpRequest(id: UUID(), fields: ["askedAt": ISO8601DateFormatter().string(from: .now)]) == nil)
    }

    @Test("Le champ envoyé ne sort pas de la liste blanche")
    func payloadStaysInAllowlist() {
        let r = HelpRequest(
            askedAt: .now, askerLabel: "x", host: "a.fr",
            verdictSummary: "s", answer: .trustworthy, answeredAt: .now, answeredBy: "y"
        )
        #expect(Set(r.recordFields.keys).isSubset(of: HelpRequest.recordKeys))
    }
}
