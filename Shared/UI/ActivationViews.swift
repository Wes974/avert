import SafariServices
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

/// Jumps straight to Safari → Extensions.
///
/// `SFSafariSettings.openExtensionsSettings(forIdentifiers:)` is a public
/// SafariServices API added in iOS 26.2 and lands directly on the extension's
/// own row. I had previously written this off as impossible and shipped a button
/// that merely opened the app's Settings page — wrong, and found out by being
/// shown uBlock Origin Lite doing it.
///
/// Below 26.2 there is no public equivalent, so the fallback opens Settings and
/// the three written steps take over. Deliberately not doing what uBOL does
/// there — bouncing through a Shortcuts `x-callback-url` whose error path
/// triggers `prefs:root=SAFARI` — because it launders a private scheme through
/// another app and needs Shortcuts installed. Three taps is a fine price for a
/// version of iOS that will be rare by the time this ships.
struct OpenSettingsButton: View {
    private static let extensionBundleID = "com.ouweis.avert.extension"

    // Not UIApplication.shared: this file is compiled into the action extension
    // too, where that symbol is unavailable. The environment action works in
    // both contexts.
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Task { await open() }
        } label: {
            HStack(spacing: 6) {
                Text("Ouvrir les réglages d'extensions")
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
        .accessibilityHint("Ouvre les réglages des extensions Safari.")
    }

    @MainActor
    private func open() async {
        if #available(iOS 26.2, *) {
            do {
                try await SFSafariSettings.openExtensionsSettings(
                    forIdentifiers: [Self.extensionBundleID]
                )
                return
            } catch {
                // Fall through: a failure here must still get the user somewhere
                // useful rather than leaving the button dead.
            }
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
