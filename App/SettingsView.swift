import SwiftUI

/// Settings (PLAN.md §7). Everything here is opt-in and off by default; the
/// on-device history is stored via Keychain, never synced (wired in M6).
struct SettingsView: View {
    @AppStorage("rememberLoginDomains") private var rememberLoginDomains = false
    @AppStorage("usePrivateCloudCompute") private var usePrivateCloudCompute = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mémoriser les domaines où je me connecte", isOn: $rememberLoginDomains)
                } header: {
                    Text("Détection de nouveauté")
                } footer: {
                    Text("Désactivé par défaut. Permet de signaler un domaine de connexion jamais vu. Stockage chiffré local (Keychain), purgeable, jamais synchronisé.")
                }

                Section {
                    Toggle("Autoriser l'analyse via Private Cloud Compute", isOn: $usePrivateCloudCompute)
                } header: {
                    Text("Analyse approfondie")
                } footer: {
                    Text("Désactivé par défaut. Pour les cas ambigus, délègue l'extraction à un modèle Apple plus grand sur Private Cloud Compute (garanties de confidentialité Apple, aucune donnée conservée). Nécessite un appareil et une version d'iOS compatibles.")
                }

                Section {
                    Button(role: .destructive) {
                        LoginHistoryStore.shared.purge()
                    } label: {
                        Label("Effacer les domaines mémorisés", systemImage: "trash")
                    }
                } footer: {
                    Text("Version 0.1.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    SettingsView()
}
