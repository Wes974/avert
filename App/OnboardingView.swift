import SwiftUI

/// First-launch onboarding.
///
/// Three pages, in the order that matters for this particular app: what it looks
/// for, how to turn it on, and — before anything else can be claimed — what it
/// cannot see. Putting the limits *in* the onboarding rather than behind a tab is
/// deliberate: the failure this product fears most is a user who believes they
/// are covered (PLAN.md §6), and that belief forms in the first thirty seconds.
///
/// No account, no permissions prompt, no data collection to disclose — so this is
/// short by nature. It ends on the one action that actually matters: opening
/// Settings to enable the extension.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private static let pageCount = 3

    var body: some View {
        ZStack {
            MidnightGround()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    purpose.tag(0)
                    activation.tag(1)
                    limits.tag(2)
                }
                // The paged style is iOS-only. On macOS the tabs keep their
                // default appearance and the two buttons below still drive the
                // sequence — swiping is not how anyone moves through a window.
                #if !os(macOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                controls
            }
            .padding(.bottom, 8)
        }
        .tint(.avertIndigo)
    }

    // MARK: - Pages

    private var purpose: some View {
        OnboardingPage(
            title: "Cette page ment-elle sur son identité ?",
            subtitle: "Avert ne consulte aucune liste noire et ne fait aucune requête réseau. Il compare ce qu'une page prétend être à ce qu'elle est vraiment."
        ) {
            AvertMark(size: 116)
                .padding(.bottom, 4)
        } content: {
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    AvertRow(icon: "key", title: "L'analyse ne démarre qu'à un moment",
                             detail: "Quand une page réclame un mot de passe, une carte, un code ou une phrase de récupération.")
                    AvertRow(icon: "speaker.slash", title: "Le reste du temps, rien ne s'affiche",
                             detail: "Pas de badge, pas de score, pas de « page sûre ». Une alerte n'a de valeur que parce qu'elle est rare.")
                }
            }
        }
    }

    private var activation: some View {
        OnboardingPage(
            title: "Avert vit dans Safari",
            subtitle: "Il faut l'y autoriser une fois. iOS ne permet à aucune app de le faire à votre place."
        ) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.avertIndigo)
                .accessibilityHidden(true)
        } content: {
            AvertCard {
                VStack(alignment: .leading, spacing: 14) {
                    ActivationSteps()
                    OpenSettingsButton()
                    Text("Avert ne peut pas vérifier que c'est fait : rien ne remonte de Safari vers l'app.")
                        .font(.caption)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var limits: some View {
        OnboardingPage(
            title: "Ce qu'Avert ne sait pas faire",
            subtitle: "Autant le dire tout de suite : une absence d'alerte ne veut pas dire qu'une page est honnête."
        ) {
            Image(systemName: "eye.slash")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.avertGold)
                .accessibilityHidden(true)
        } content: {
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    AvertRow(icon: "list.bullet.rectangle", title: "Il ne connaît qu'une liste de marques",
                             detail: "Face à une marque absente de son registre, il ne peut comparer aucune identité.", tone: .neutral)
                    AvertRow(icon: "figure.run", title: "Un attaquant qui l'étudie peut le contourner",
                             detail: "Il croise plusieurs indices pour rendre l'évasion coûteuse, pas impossible.", tone: .neutral)
                    AvertRow(icon: "checkmark.shield", title: "Il peut se tromper",
                             detail: "Une alerte reste toujours contournable. C'est vous qui décidez.", tone: .neutral)
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.avertIndigo : Color.avertInkSoft.opacity(0.3))
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .animation(.snappy(duration: 0.25), value: page)
                }
            }
            .accessibilityHidden(true)

            Button {
                if page < Self.pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    isPresented = false
                }
            } label: {
                Text(page < Self.pageCount - 1 ? "Continuer" : "Commencer")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.avertIndigo)
                    )
                    .foregroundStyle(.white)
            }

            // Always available: nobody should be trapped in an onboarding, least
            // of all in an app whose whole argument is that you stay in control.
            Button("Passer") { isPresented = false }
                .font(.subheadline)
                .foregroundStyle(Color.avertInkSoft)
                .opacity(page < Self.pageCount - 1 ? 1 : 0)
                .disabled(page == Self.pageCount - 1)
        }
        .padding(.horizontal, 24)
        .readableWidth()
    }
}

/// One onboarding page: an illustration, a title, a subtitle, and a body card.
private struct OnboardingPage<Illustration: View, Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var illustration: () -> Illustration
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    illustration()
                    Spacer()
                }
                .padding(.top, 24)
                .padding(.bottom, 8)

                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(Color.avertInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.avertInkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
