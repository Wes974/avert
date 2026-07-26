import SwiftUI

/// Family mode: alerts a relative when a strong warning is ignored, and lets
/// someone ask a relative whether a page is genuine.
///
/// This is the one place in Avert where data leaves the device, so the screen
/// says what travels before anything else, in the same words whether the feature
/// is on or off. An app that spends three screens explaining what it cannot see
/// does not get to be coy about the one thing it sends.
///
/// Directions are always spelled out. The property worth protecting is not that
/// links are symmetric — a relative looking after several people is a legitimate
/// arrangement — it is that nobody can be watched without knowing it.
struct FamilyView: View {
    @State private var snapshot = FamilySnapshot()
    @State private var busy = false
    @State private var confirmingUnlink = false
    @State private var deviceLabel = FamilyDeviceLabel.current

    let store: FamilyStore

    private var peers: [FamilyPeer] {
        if case .linked(let p) = snapshot.state { return p }
        return []
    }
    private var watchers: [FamilyPeer] { peers.filter { $0.direction == .theyWatchMe } }
    private var watched: [FamilyPeer] { peers.filter { $0.direction == .iWatchThem } }

    var body: some View {
        MidnightScreen(
            title: "Mode famille",
            subtitle: "Prévenir un proche quand un avertissement fort est ignoré, et pouvoir lui demander si une page est fiable."
        ) {
            whatTravels
            labelField

            if case .unavailable(let reason) = snapshot.state {
                AvertCard {
                    AvertRow(icon: "icloud.slash", title: "Indisponible",
                             detail: LocalizedStringKey(reason), tone: .neutral)
                }
            } else {
                if !snapshot.incoming.isEmpty { incomingRequests }
                if !snapshot.mine.isEmpty { myRequests }
                links
                if !snapshot.alerts.isEmpty { alertHistory }
                invitationCard
                if !peers.isEmpty || snapshot.invitation != nil { unlink }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: - The honest part, shown first and always

    private var whatTravels: some View {
        AvertCard {
            VStack(alignment: .leading, spacing: 12) {
                AvertRow(icon: "bell.badge", title: "Alerte automatique",
                         detail: "Quand vous ignorez un avertissement fort, vos proches liés apprennent que c'est arrivé. Jamais sur quel site : ni l'adresse ni la marque ne sont envoyées.",
                         tone: .gold)
                AvertRow(icon: "questionmark.bubble", title: "Demander à un proche",
                         detail: "Là, l'adresse est envoyée — c'est la question. Vous la voyez avant d'envoyer, et la demande s'efface au bout de 24 heures.")
                AvertRow(icon: "eye", title: "Rien ne se fait en secret",
                         detail: "Chaque lien est affiché dans les deux sens, sur les deux appareils, et peut être rompu à tout moment.")
            }
        }
    }

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

    // MARK: - Questions asked of me

    private var incomingRequests: some View {
        VStack(alignment: .leading, spacing: 18) {
            AvertSectionLabel(text: "On vous demande votre avis")
            ForEach(snapshot.incoming) { request in
                AvertCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(request.askerLabel) demande si ce site est fiable :")
                            .font(.subheadline)
                            .foregroundStyle(Color.avertInk)
                            .fixedSize(horizontal: false, vertical: true)
                        // Monospaced and never truncated mid-string: judging a
                        // domain means reading every character of it.
                        Text(request.host)
                            .font(.callout.monospaced().weight(.semibold))
                            .foregroundStyle(Color.avertInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let summary = request.verdictSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(Color.avertInkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let answer = request.answer {
                            Text("Vous avez répondu : \(Self.label(for: answer))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.avertInkSoft)
                        } else {
                            HStack(spacing: 8) {
                                answerButton(.dangerous, "Dangereux", request)
                                answerButton(.unsure, "Je ne sais pas", request)
                                answerButton(.trustworthy, "Fiable", request)
                            }
                        }
                    }
                }
            }
        }
    }

    private func answerButton(
        _ answer: HelpRequest.Answer, _ title: LocalizedStringKey, _ request: HelpRequest
    ) -> some View {
        Button {
            Task { await reply(to: request, with: answer) }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(answer == .dangerous ? Color.avertGold.opacity(0.18)
                              : Color.avertIndigo.opacity(0.14))
                )
                .foregroundStyle(answer == .dangerous ? Color.avertGold : Color.avertIndigo)
        }
        .disabled(busy)
    }

    private static func label(for answer: HelpRequest.Answer) -> String {
        switch answer {
        case .trustworthy: String(localized: "family.answer.trustworthy")
        case .dangerous: String(localized: "family.answer.dangerous")
        case .unsure: String(localized: "family.answer.unsure")
        }
    }

    // MARK: - My own questions

    private var myRequests: some View {
        VStack(alignment: .leading, spacing: 18) {
            AvertSectionLabel(text: "Vos demandes")
            AvertCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(snapshot.mine) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.host)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Color.avertInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if let answer = request.answer {
                                Text("\(request.answeredBy ?? "") : \(Self.label(for: answer))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(answer == .dangerous ? Color.avertGold : Color.avertInk)
                            } else {
                                Text("En attente d'une réponse…")
                                    .font(.caption)
                                    .foregroundStyle(Color.avertInkSoft)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Links, in both directions

    private var links: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !watchers.isEmpty {
                AvertSectionLabel(text: "Reçoivent vos alertes")
                AvertCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(watchers) { peer in
                            AvertRow(icon: "arrow.up.right.circle", title: LocalizedStringKey(peer.label),
                                     detail: "Voit vos avertissements ignorés et peut répondre à vos demandes.")
                        }
                    }
                }
            }
            if !watched.isEmpty {
                AvertSectionLabel(text: "Vous suivez")
                AvertCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(watched) { peer in
                            AvertRow(icon: "arrow.down.left.circle", title: LocalizedStringKey(peer.label),
                                     detail: "Vous recevez ses avertissements ignorés et ses demandes.")
                        }
                    }
                }
            }
        }
    }

    private var alertHistory: some View {
        VStack(alignment: .leading, spacing: 18) {
            AvertSectionLabel(text: "Avertissements ignorés")
            AvertCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.alerts) { alert in
                        AvertRow(icon: "exclamationmark.triangle",
                                 title: LocalizedStringKey(alert.message()), tone: .gold)
                    }
                }
            }
        }
    }

    // MARK: - Invitation

    private var invitationCard: some View {
        AvertCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(snapshot.invitation == nil
                     ? "Invitez un proche à recevoir vos alertes et à répondre à vos demandes."
                     : "Invitation prête. Envoyez-la à la personne de votre choix.")
                    .font(.subheadline)
                    .foregroundStyle(Color.avertInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let invitation = snapshot.invitation {
                    ShareLink(item: invitation) {
                        Text("Envoyer l'invitation")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.avertIndigo))
                            .foregroundStyle(.white)
                    }
                    // Says out loud that a link is one-way, so nobody assumes a
                    // reciprocity they never set up.
                    Text("Pour qu'un proche vous partage aussi les siennes, il doit vous envoyer sa propre invitation. Un lien ne va que dans un sens.")
                        .font(.caption)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        Task { await invite() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Préparation…" : "Créer une invitation")
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

    private var unlink: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) { confirmingUnlink = true } label: {
                Text("Tout rompre")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .confirmationDialog("Rompre tous les liens ?", isPresented: $confirmingUnlink, titleVisibility: .visible) {
                Button("Tout rompre", role: .destructive) { Task { await unlinkAll() } }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Personne ne recevra plus vos alertes, et vous ne recevrez plus les leurs. Tout ce que cet appareil a envoyé est supprimé.")
            }
            Text("Vous pouvez rompre à tout moment, sans prévenir personne.")
                .font(.caption)
                .foregroundStyle(Color.avertInkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Actions

    private func refresh() async {
        snapshot = await store.snapshot()
    }

    private func invite() async {
        busy = true
        defer { busy = false }
        guard let cloud = store as? CloudKitFamilyStore else { return }
        _ = try? await cloud.createInvitation()
        await refresh()
    }

    private func reply(to request: HelpRequest, with answer: HelpRequest.Answer) async {
        busy = true
        defer { busy = false }
        try? await store.answer(request, with: answer, as: deviceLabel)
        await refresh()
    }

    private func unlinkAll() async {
        try? await store.unlinkAll()
        await refresh()
    }
}

#Preview("Non configuré") {
    FamilyView(store: InMemoryFamilyStore())
}
