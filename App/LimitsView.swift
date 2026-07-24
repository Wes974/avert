import SwiftUI

/// "Ce que cette extension ne voit pas" (PLAN.md §6, §8). The single most
/// important screen against the deepest risk — a false sense of security.
/// The limits are stated plainly, never buried.
struct LimitsView: View {
    private struct Limit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let limits: [Limit] = [
        .init(icon: "list.bullet.rectangle",
              title: "Une marque hors de mon registre n'est pas vérifiable",
              detail: "Je ne connais qu'une liste de marques (banques, services). Face à une marque absente, je ne peux comparer aucune identité — seulement repérer des schémas d'arnaque génériques."),
        .init(icon: "figure.run",
              title: "Un attaquant qui m'étudie peut me contourner",
              detail: "Le phishing s'adapte plus vite qu'une défense. Je croise plusieurs indices pour rendre l'évasion coûteuse, pas impossible."),
        .init(icon: "checkmark.shield",
              title: "Je peux me tromper (faux positif)",
              detail: "Certains prestataires d'authentification légitimes ressemblent à une incohérence d'identité. Une alerte reste toujours contournable — c'est vous qui décidez."),
        .init(icon: "eye.slash",
              title: "Je ne vois pas tout d'une page",
              detail: "Certaines techniques (formulaires reconstruits en image, protections avancées) échappent à mon analyse. Une absence d'alerte ne garantit rien."),
        .init(icon: "network.slash",
              title: "Je ne vérifie ni le certificat ni l'âge du domaine",
              detail: "Safari ne me donne pas accès à ces informations sans réseau. Je m'appuie sur l'identité revendiquée et la structure de la page, pas sur la réputation du domaine."),
        .init(icon: "envelope.badge.shield.half.filled",
              title: "Je ne vois que Safari",
              detail: "Un lien ouvert dans une autre app, un SMS, un mail, un QR code : hors de ma portée jusqu'à ce que la page s'ouvre dans Safari."),
    ]

    var body: some View {
        MidnightScreen(
            title: "Limites",
            subtitle: "Avert réduit un risque, il ne l'élimine pas. Vous restez la dernière ligne de défense."
        ) {
            AvertSectionLabel(text: "Ce que je ne vois pas")
            ForEach(limits) { limit in
                AvertCard {
                    // Neutral glyphs on purpose: these are honest statements, not
                    // warnings. Gold stays reserved for actual caution.
                    AvertRow(icon: limit.icon, title: limit.title, detail: limit.detail, tone: .neutral)
                }
            }

            AvertCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pourquoi cet écran existe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.avertInk)
                    Text("Le pire échec possible pour un outil comme Avert n'est pas de rater un site : c'est de vous faire croire que vous êtes couvert. Ce que je ne sais pas faire est écrit ici, pas caché dans une page d'aide.")
                        .font(.footnote)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    LimitsView()
}
