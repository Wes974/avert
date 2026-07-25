import SwiftUI

/// The activation instructions, shared by the onboarding and the Home tab.
///
/// One copy, because these three steps are the single most consequential text in
/// the app: get them wrong and the extension is simply never enabled. Two
/// divergent versions of them was a bug waiting to happen.
struct ActivationSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepRow(number: 1, text: "Réglages → Apps → Safari → Extensions")
            StepRow(number: 2, text: "Activer **Avert**")
            StepRow(number: 3, text: "Autoriser sur tous les sites (« Toujours autoriser »)")
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

/// Opens the Settings app.
///
/// It lands on Avert's own Settings page, **not** on Safari → Extensions, and the
/// label says so. iOS publishes exactly one URL for this
/// (`UIApplication.openSettingsURLString`); the deep link that would jump
/// straight to the extension list, `App-prefs:root=SAFARI&path=WEB_EXTENSIONS`,
/// is a private scheme and a documented cause of App Store rejection. Promising
/// a shortcut that iOS does not offer — or risking the app's review over three
/// taps — is not a trade this app makes.
struct OpenSettingsButton: View {
    var body: some View {
        Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
            HStack(spacing: 6) {
                Text("Ouvrir les Réglages")
                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.avertIndigo.opacity(0.14))
            )
            .foregroundStyle(Color.avertIndigo)
        }
        .accessibilityHint("Ouvre les Réglages d'iOS. Naviguez ensuite vers Apps, puis Safari, puis Extensions.")
    }
}
