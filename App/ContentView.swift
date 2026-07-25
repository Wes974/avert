import SwiftUI

struct ContentView: View {
    /// Shown once. Stored in plain UserDefaults — this is a UI preference, not
    /// something worth a Keychain entry, and it is the only state the app keeps.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

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
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onAppear {
            guard !hasSeenOnboarding else { return }
            showOnboarding = true
            // Marked as seen on appearance rather than on completion: someone who
            // force-quits mid-onboarding has still made a choice about it, and
            // being shown it again would be nagging. Everything it says is on the
            // Home and Limits tabs anyway.
            hasSeenOnboarding = true
        }
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
                    ActivationSteps()
                    OpenSettingsButton()
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

#Preview {
    ContentView()
}
