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
        MidnightScreen(title: "Réglages") {
            AvertSectionLabel(text: "Confidentialité")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    AvertRow(icon: "lock.shield", title: "Aucune donnée de page ne quitte votre appareil")
                    AvertRow(icon: "hand.raised", title: "Aucune télémétrie, aucun compte, aucune publicité")
                    Divider().overlay(Color.avertHairline.opacity(0.12))
                    Text("Avert analyse les pages localement. Aucune adresse, aucun contenu n'est envoyé où que ce soit.")
                        .font(.footnote)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AvertSectionLabel(text: "À propos")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Version")
                            .font(.subheadline)
                            .foregroundStyle(Color.avertInk)
                        Spacer()
                        Text(appVersion)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.avertInkSoft)
                    }
                    Divider().overlay(Color.avertHairline.opacity(0.12))
                    Link(destination: URL(string: "https://www.apple.com/legal/privacy/")!) {
                        HStack {
                            AvertRow(icon: "doc.text", title: "Politique de confidentialité")
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.avertInkSoft)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
