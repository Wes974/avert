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
              detail: "Certains prestataires d'authentification légitimes ressemblent à une incohérence d'identité. Vous pouvez toujours continuer, et signaler l'erreur."),
        .init(icon: "eye.slash",
              title: "Je ne vois pas tout d'une page",
              detail: "Certaines techniques (formulaires reconstruits en image, protections avancées) échappent à mon analyse. Une absence d'alerte ne garantit rien."),
        .init(icon: "network.slash",
              title: "Je ne vérifie ni le certificat ni l'âge du domaine",
              detail: "Safari ne me donne pas accès à ces informations sans réseau. Je m'appuie sur l'identité revendiquée et la structure de la page, pas sur la réputation du domaine."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Impostor réduit un risque, il ne l'élimine pas. Restez la dernière ligne de défense.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Ce que je ne vois pas") {
                    ForEach(limits) { limit in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(limit.title, systemImage: limit.icon)
                                .font(.subheadline.weight(.semibold))
                            Text(limit.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Limites")
        }
    }
}

#Preview {
    LimitsView()
}
