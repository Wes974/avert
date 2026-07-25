import SwiftUI

/// Result view for a link check, shared by the App Intent snippet and the share
/// extension. Midnight direction, same restraint as the in-page alert: state the
/// verdict, give the reasons, never hide the caveat.
struct LinkCheckSnippet: View {
    private let check: LinkCheck?
    private let rawInput: String

    init(check: LinkCheck) {
        self.check = check
        self.rawInput = check.host
    }

    init(notALink input: String) {
        self.check = nil
        self.rawInput = input
    }

    private var tone: AvertRow.Tone {
        switch check?.level {
        case .impersonation: .gold
        case .suspicious: .indigo
        default: .neutral
        }
    }

    private var glyph: String {
        switch check?.level {
        case .impersonation: "exclamationmark.triangle.fill"
        case .suspicious: "questionmark.circle.fill"
        case .nothingFound: "checkmark.circle"
        case nil: "link.slash"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: glyph)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tone == .gold ? Color.avertGold : Color.avertIndigo)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(check?.headline ?? String(localized: "link.error.not-a-link"))
                        .font(.headline)
                        .foregroundStyle(Color.avertInk)
                        .fixedSize(horizontal: false, vertical: true)
                    // The host, monospaced and never truncated in the middle:
                    // the whole point is that the user can read the real domain.
                    Text(rawInput)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.avertInkSoft)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }

            Text(check?.explanation ?? String(localized: "link.error.not-a-link.detail"))
                .font(.subheadline)
                .foregroundStyle(Color.avertInk)
                .fixedSize(horizontal: false, vertical: true)

            if let findings = check?.findings, !findings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(findings, id: \.self) { finding in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.avertInkSoft)
                                .frame(width: 4, height: 4)
                                .accessibilityHidden(true)
                            Text(finding)
                                .font(.footnote)
                                .foregroundStyle(Color.avertInkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let check {
                Text(check.caveat)
                    .font(.caption)
                    .foregroundStyle(Color.avertInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.avertSurface)
    }
}

#Preview("Usurpation") {
    LinkCheckSnippet(check: LinkCheck(
        level: .impersonation,
        host: "paypal.com.securite-client.xyz",
        brand: "PayPal",
        signals: [
            L1Signal(id: "l1.brand-subdomain", detail: "paypal.com.securite-client.xyz", brand: "PayPal"),
            L1Signal(id: "l1.low-rep-tld", detail: "xyz", brand: nil),
        ]
    ))
}

#Preview("Rien trouvé") {
    LinkCheckSnippet(check: LinkCheck(
        level: .nothingFound, host: "www.impots.gouv.fr", brand: nil, signals: []
    ))
}
