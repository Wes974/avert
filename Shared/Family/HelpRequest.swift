import Foundation

/// "Ask someone you trust": the page *is* the question.
///
/// Read `FamilyAlert` next to this type — they are opposites on purpose.
///
/// `FamilyAlert` fires on its own, so it may carry nothing that identifies a
/// destination. A `HelpRequest` is typed out by the person, about this page, at
/// this moment, and the whole point is for a relative to look at the address and
/// say whether it is genuine. Sending the host is not a leak here; it is the
/// message. Withholding it would leave the question unanswerable and the feature
/// pointless.
///
/// What separates the two is not how much data moves. It is who started it, and
/// how far it reaches:
///
///   FamilyAlert   automatic · every ignored warning · no destination, ever
///   HelpRequest   deliberate · one page, one time · the destination is the point
///
/// The guarantees that keep this honest are elsewhere in the flow, and they are
/// not optional: the asker sees the exact host before sending, and the request is
/// deleted once answered (`HelpRequest.expiry`). A pile of past questions would
/// become the browsing log this app refuses to build.
struct HelpRequest: Identifiable, Equatable, Sendable {
    enum Answer: String, Sendable, CaseIterable {
        case trustworthy
        case dangerous
        /// Also a real answer. A relative who is unsure should be able to say so
        /// rather than guess — a wrong "it's fine" is worse than no answer.
        case unsure
    }

    let id: UUID
    let askedAt: Date
    /// How the asker is known, same field as `FamilyAlert.deviceLabel`.
    let askerLabel: String
    /// The host being asked about. Present *because* the user asked.
    let host: String
    /// What Avert itself concluded, so the relative is not judging blind.
    let verdictSummary: String?

    var answer: Answer?
    var answeredAt: Date?
    var answeredBy: String?

    init(
        id: UUID = UUID(),
        askedAt: Date,
        askerLabel: String,
        host: String,
        verdictSummary: String? = nil,
        answer: Answer? = nil,
        answeredAt: Date? = nil,
        answeredBy: String? = nil
    ) {
        self.id = id
        self.askedAt = Date(timeIntervalSince1970: askedAt.timeIntervalSince1970.rounded())
        self.askerLabel = String(askerLabel.prefix(FamilyAlert.maxLabelLength))
        // Host only — never a full URL. A path or query can carry a session
        // token or a magic link, and none of that helps anyone judge a domain.
        self.host = Self.hostOnly(host)
        self.verdictSummary = verdictSummary
        self.answer = answer
        self.answeredAt = answeredAt
        self.answeredBy = answeredBy
    }

    /// Strips anything beyond the host if a full URL slips in.
    static func hostOnly(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        s = s.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" }).description
        return String(s.lowercased().prefix(253))
    }

    /// Requests older than this are dropped, answered or not. The value of an
    /// unanswered question decays to nothing within hours, and keeping them
    /// would build the very history this app exists to avoid.
    static let expiry: TimeInterval = 24 * 3600

    func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(askedAt) > Self.expiry
    }

    var isAnswered: Bool { answer != nil }
}

// MARK: - Wire format

extension HelpRequest {
    static let recordType = "HelpRequest"

    /// Allowlist, exactly as for `FamilyAlert` — the difference between the two
    /// features is visible right here, in one line, and asserted by tests.
    static let recordKeys: Set<String> = [
        "askedAt", "askerLabel", "host", "verdictSummary",
        "answer", "answeredAt", "answeredBy",
    ]

    var recordFields: [String: String] {
        let iso = ISO8601DateFormatter()
        var fields = [
            "askedAt": iso.string(from: askedAt),
            "askerLabel": askerLabel,
            "host": host,
        ]
        if let verdictSummary { fields["verdictSummary"] = verdictSummary }
        if let answer { fields["answer"] = answer.rawValue }
        if let answeredAt { fields["answeredAt"] = iso.string(from: answeredAt) }
        if let answeredBy { fields["answeredBy"] = answeredBy }
        return fields
    }

    init?(id: UUID, fields: [String: String]) {
        let iso = ISO8601DateFormatter()
        guard let rawDate = fields["askedAt"], let date = iso.date(from: rawDate),
              let host = fields["host"]
        else { return nil }
        self.init(
            id: id,
            askedAt: date,
            askerLabel: fields["askerLabel"] ?? "",
            host: host,
            verdictSummary: fields["verdictSummary"],
            answer: fields["answer"].flatMap(Answer.init(rawValue:)),
            answeredAt: fields["answeredAt"].flatMap(iso.date(from:)),
            answeredBy: fields["answeredBy"]
        )
    }
}
