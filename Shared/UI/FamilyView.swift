import SwiftUI

/// Family mode: the screen where someone decides to let a relative know when
/// they ignore a strong warning — and to be told the same about that relative.
///
/// This is the one place in Avert where data leaves the device, so the screen
/// says so before anything else, in the same words whether the feature is on or
/// off. An app that spends three screens explaining what it cannot see does not
/// get to be coy about the one thing it sends.
struct FamilyView: View {
    @State private var state: FamilyLinkState = .off
    @State private var alerts: [FamilyAlert] = []
    @State private var invitation: URL?
    @State private var busy = false
    @State private var confirmingUnlink = false
    @State private var deviceLabel = FamilyDeviceLabel.current

    let store: FamilyStore

    var body: some View {
        MidnightScreen(
            title: "Mode famille",
            subtitle: "Prévenir un proche quand un avertissement fort est ignoré — et être prévenu pour lui."
        ) {
            whatTravels
            labelField

            switch state {
            case .unavailable(let reason):
                AvertCard {
                    AvertRow(icon: "icloud.slash", title: "Indisponible", detail: LocalizedStringKey(reason), tone: .neutral)
                }
            case .off:
                setup
            case .linked(let peers):
                linked(peers)
                if !alerts.isEmpty { history }
                unlink
            }
        }
        .task { await refresh() }
    }

    // MARK: - The honest part, shown first and always

    private var whatTravels: some View {
        AvertCard {
            VStack(alignment: .leading, spacing: 12) {
                AvertRow(icon: "arrow.up.forward.circle", title: "Ce qui quitte l'appareil",
                         detail: "Uniquement ceci : la date, et le nom que vous donnez à cet appareil. Rien d'autre ne peut être envoyé.",
                         tone: .gold)
                AvertRow(icon: "eye.slash", title: "Ce qui ne part jamais",
                         detail: "Ni le site visité, ni la marque concernée, ni l'adresse. Votre proche apprend qu'un avertissement a été ignoré, pas où.")
                AvertRow(icon: "arrow.left.arrow.right", title: "Le lien est réciproque",
                         detail: "Vous voyez ses avertissements ignorés, il voit les vôtres. Il n'existe pas de version à sens unique.")
            }
        }
    }

    // MARK: - States

    /// The label doubles as the on/off switch: empty means nothing is ever
    /// published. One state instead of a name plus a boolean that could drift
    /// apart — see `FamilyDeviceLabel`.
    private var labelField: some View {
        AvertCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Le nom de cet appareil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.avertInk)
                TextField("iPhone de Papa", text: $deviceLabel)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: deviceLabel) { _, new in FamilyDeviceLabel.set(new) }
                Text("C'est le seul mot que vos proches verront. Choisissez-le : il n'est pas repris du nom de votre appareil, qui contient souvent votre nom complet.")
                    .font(.caption)
                    .foregroundStyle(Color.avertInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if deviceLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Tant que ce champ est vide, rien n'est jamais envoyé.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.avertGold)
                }
            }
        }
    }

    private var setup: some View {
        AvertCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Aucun proche n'est lié à cet appareil.")
                    .font(.subheadline)
                    .foregroundStyle(Color.avertInk)

                if let invitation {
                    ShareLink(item: invitation) {
                        Text("Envoyer l'invitation")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.avertIndigo))
                            .foregroundStyle(.white)
                    }
                    Text("L'invitation ne fonctionne que pour la personne à qui vous l'envoyez.")
                        .font(.caption)
                        .foregroundStyle(Color.avertInkSoft)
                } else {
                    Button {
                        Task { await invite() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Préparation…" : "Créer un lien familial")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.avertIndigo))
                        .foregroundStyle(.white)
                    }
                    .disabled(busy)
                }
            }
        }
    }

    private func linked(_ peers: [FamilyPeer]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            AvertSectionLabel(text: "Proches liés")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(peers) { peer in
                        AvertRow(icon: "person.crop.circle", title: LocalizedStringKey(peer.label))
                    }
                    if peers.isEmpty {
                        Text("L'invitation est envoyée, personne ne l'a encore acceptée.")
                            .font(.footnote)
                            .foregroundStyle(Color.avertInkSoft)
                    }
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            AvertSectionLabel(text: "Avertissements ignorés")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(alerts) { alert in
                        AvertRow(icon: "exclamationmark.triangle",
                                 title: LocalizedStringKey(alert.message()),
                                 tone: .gold)
                    }
                }
            }
        }
    }

    private var unlink: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) { confirmingUnlink = true } label: {
                Text("Rompre le lien")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .confirmationDialog("Rompre le lien familial ?", isPresented: $confirmingUnlink, titleVisibility: .visible) {
                Button("Rompre le lien", role: .destructive) { Task { await unlinkAll() } }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Vos proches ne seront plus prévenus, et vous ne le serez plus pour eux. Tout ce que cet appareil a envoyé est supprimé.")
            }
            Text("Vous pouvez rompre le lien à tout moment, sans prévenir personne.")
                .font(.caption)
                .foregroundStyle(Color.avertInkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        state = await store.currentState()
        alerts = (try? await store.receivedAlerts(limit: 20)) ?? []
    }

    private func invite() async {
        busy = true
        defer { busy = false }
        guard let cloud = store as? CloudKitFamilyStore else { return }
        invitation = try? await cloud.createInvitation()
        await refresh()
    }

    private func unlinkAll() async {
        try? await store.unlinkAll()
        invitation = nil
        await refresh()
    }
}

#Preview("Lié") {
    FamilyView(store: InMemoryFamilyStore(
        state: .linked(peers: [FamilyPeer(id: "1", label: "iPhone de Papa", lastHeardFrom: nil)]),
        received: [FamilyAlert(occurredAt: .now.addingTimeInterval(-3600), deviceLabel: "iPhone de Papa")]
    ))
}

#Preview("Non configuré") {
    FamilyView(store: InMemoryFamilyStore())
}
