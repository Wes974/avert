import SwiftUI

/// Settings (PLAN.md §7).
///
/// Honesty rule: this screen shows only what actually works. The opt-in login
/// history and the Private Cloud Compute escalation both depend on plumbing
/// that isn't wired yet (app group entitlement for history; iOS 27 + managed
/// entitlement for PCC), so their toggles are intentionally absent rather than
/// present-but-fake. They come back the moment the plumbing lands.
struct SettingsView: View {
    /// The build number stays hidden until asked for, the way Settings › General
    /// › About does it. The version is what a user might mention; the build is
    /// what a developer needs, and putting both up front makes the row read like
    /// a serial number to everyone else.
    @State private var showsBuild = false

    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var displayedVersion: String {
        showsBuild ? "\(marketingVersion) (\(buildNumber))" : marketingVersion
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

            AvertSectionLabel(text: "Famille")
            AvertCard {
                NavigationLink {
                    FamilyView(store: CloudKitFamilyStore())
                } label: {
                    HStack {
                        AvertRow(icon: "person.2", title: "Mode famille",
                                 detail: "Prévenir un proche quand un avertissement fort est ignoré. Désactivé par défaut.")
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.avertInkSoft)
                    }
                    .frame(minHeight: 44)
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
                        Text(displayedVersion)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.avertInkSoft)
                            // contentTransition keeps the digits in place while
                            // the build number slides in, instead of the row
                            // jumping.
                            .contentTransition(.numericText())
                    }
                    // The whole row is the target, not just the number: a 44 pt
                    // strip is findable, a short string is not.
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.2)) { showsBuild.toggle() }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(showsBuild
                                       ? "Toucher pour masquer le numéro de build."
                                       : "Toucher pour afficher le numéro de build.")
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
