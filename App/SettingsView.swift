import SwiftUI

/// Settings (PLAN.md §7).
///
/// Honesty rule: this screen shows only what actually works. The opt-in login
/// history and the Private Cloud Compute escalation both depend on plumbing
/// that isn't wired yet (app group entitlement for history; iOS 27 + managed
/// entitlement for PCC), so their toggles are intentionally absent rather than
/// present-but-fake. They come back the moment the plumbing lands.
struct SettingsView: View {
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Aucune donnée de page ne quitte votre appareil.", systemImage: "lock.shield")
                    Label("Aucune télémétrie, aucun compte, aucune publicité.", systemImage: "hand.raised")
                } header: {
                    Text("Confidentialité")
                } footer: {
                    Text("Impostor analyse les pages localement. Aucune adresse, aucun contenu n’est envoyé où que ce soit.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    Link(destination: URL(string: "https://www.apple.com/legal/privacy/")!) {
                        Label("Politique de confidentialité", systemImage: "doc.text")
                    }
                } header: {
                    Text("À propos")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    SettingsView()
}
