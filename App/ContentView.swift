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
    }
}

private struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Activation") {
                    Label(
                        "Activez Avert dans Réglages → Apps → Safari → Extensions, puis autorisez-la sur tous les sites.",
                        systemImage: "puzzlepiece.extension"
                    )
                }
                Section("Principe") {
                    Text("Avert n'alerte pas parce qu'un site figure sur une liste noire — il n'en utilise aucune. Il repère quand une page **réclame une identité** (une marque, une banque) qui ne correspond pas au domaine qui l'héberge.")
                    Text("La plupart des pages ne déclenchent rien : l'analyse ne démarre que sur une page qui demande un mot de passe, un paiement, un code ou une phrase de récupération.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                Section("Confidentialité") {
                    Label("Aucune donnée de page ne quitte votre appareil.", systemImage: "lock.shield")
                    Label("Aucune télémétrie, aucun compte.", systemImage: "person.crop.circle.badge.xmark")
                }
            }
            .navigationTitle("Avert")
        }
    }
}

#Preview {
    ContentView()
}
