import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house") }
            LimitsView()
                .tabItem { Label("Limites", systemImage: "eye.slash") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .tint(.avertIndigo)
    }
}

private struct HomeView: View {
    /// The four steps of the cascade, in the words of what the user gets — not
    /// in internal L0/L1/L2/L3 jargon.
    private static let cascade: [(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        ("key", "Une page demande un secret",
         "Mot de passe, carte, code, phrase de récupération : c'est le seul moment où l'analyse démarre."),
        ("link", "L'adresse est examinée",
         "Caractères trompeurs, marque greffée sur un domaine étranger, structure inhabituelle."),
        ("doc.text.magnifyingglass", "La page est examinée",
         "Champ caché, formulaire qui poste ailleurs, logo emprunté à une marque connue."),
        ("sparkles", "L'identité revendiquée est extraite",
         "Le modèle sur l'appareil dit quelle marque la page prétend être. Avert compare — et c'est cette comparaison qui décide."),
    ]

    var body: some View {
        MidnightScreen(title: "Avert") {
            AvertCard {
                HStack(alignment: .center, spacing: 16) {
                    AvertMark(size: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cette page ment-elle sur son identité ?")
                            .font(.headline)
                            .foregroundStyle(Color.avertInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Aucune liste noire. Aucun réseau. Une comparaison.")
                            .font(.footnote)
                            .foregroundStyle(Color.avertInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            AvertSectionLabel(text: "Activation")
            AvertCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Avert vit dans Safari. Trois réglages à faire une fois :")
                        .font(.subheadline)
                        .foregroundStyle(Color.avertInk)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        StepRow(number: 1, text: "Réglages → Apps → Safari → Extensions")
                        StepRow(number: 2, text: "Activer **Avert**")
                        StepRow(number: 3, text: "Autoriser sur tous les sites (« Toujours autoriser »)")
                    }
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Text("Ouvrir les Réglages")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.avertIndigo.opacity(0.14))
                            )
                            .foregroundStyle(Color.avertIndigo)
                    }
                    Text("Avert ne peut pas savoir si vous avez fait ces trois étapes : rien ne remonte de Safari vers l'app.")
                        .font(.caption)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AvertSectionLabel(text: "Comment ça marche")
            AvertCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(Self.cascade.enumerated()), id: \.offset) { _, step in
                        AvertRow(icon: step.icon, title: step.title, detail: step.detail)
                    }
                }
            }

            AvertSectionLabel(text: "Silence par défaut")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    AvertRow(icon: "speaker.slash", title: "Rien ne s'affiche sur une page normale",
                             detail: "Pas de badge, pas de score, pas de « page sûre ». Une alerte veut dire quelque chose parce qu'elle est rare.")
                    AvertRow(icon: "arrow.triangle.branch", title: "Jamais d'alerte sur un seul indice",
                             detail: "Plusieurs signaux doivent converger, et une alerte forte exige en plus une incohérence d'identité confirmée.", tone: .gold)
                    AvertRow(icon: "hand.raised.slash", title: "Vous pouvez toujours continuer",
                             detail: "Avert explique et ralentit. Il ne bloque pas.")
                }
            }

            AvertSectionLabel(text: "Confidentialité")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    AvertRow(icon: "lock.shield", title: "Aucune donnée de page ne quitte l'appareil")
                    AvertRow(icon: "person.crop.circle.badge.xmark", title: "Aucune télémétrie, aucun compte")
                    AvertRow(icon: "network.slash", title: "Aucune requête réseau, même pour vérifier une marque")
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.avertIndigo)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.avertIndigo.opacity(0.14)))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.avertInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        // The number badge is decorative (hidden), so VoiceOver needs it spoken
        // here or the steps lose their order.
        .accessibilityLabel(Text("Étape \(number) : \(Text(text))"))
    }
}

#Preview {
    ContentView()
}
