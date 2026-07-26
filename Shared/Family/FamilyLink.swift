import Foundation

/// State of the family link on this device.
///
/// Symmetric by construction: linking two people means each sees the other's
/// ignored warnings. There is no watcher/watched asymmetry, and that is the
/// point — a one-way version would be surveillance wearing a safety label, and a
/// child who can also see their parent's alerts understands immediately what the
/// feature does.
enum FamilyLinkState: Equatable, Sendable {
    /// Never set up. The default, and the state most users stay in.
    case off
    /// Container or entitlement missing — the feature cannot work at all.
    /// Surfaced as unavailable rather than broken, and never as "on".
    case unavailable(reason: String)
    /// Set up, with the people currently linked.
    case linked(peers: [FamilyPeer])

    var isActive: Bool {
        if case .linked(let peers) = self { return !peers.isEmpty }
        return false
    }
}

struct FamilyPeer: Identifiable, Equatable, Sendable {
    /// Which way the link runs. Shown in both apps, always: the property worth
    /// protecting is not symmetry, it is that nobody can be watched without
    /// knowing it. An asymmetric link is fine — a hidden one is not.
    enum Direction: Sendable {
        /// They see my ignored warnings and can answer my questions.
        case theyWatchMe
        /// I see theirs.
        case iWatchThem
    }

    let id: String
    /// How they chose to be known. Their label, not one we assigned.
    let label: String
    /// When we last received anything from them. Nil means never — worth
    /// showing, because a link that has gone quiet may simply be broken, and a
    /// safety feature that has silently stopped working is worse than none.
    let lastHeardFrom: Date?
    let direction: Direction
}

/// Everything the family feature needs from storage.
///
/// A protocol so the rules above can be tested without CloudKit, an iCloud
/// account, or a network. The CloudKit implementation stays deliberately thin:
/// anything worth testing lives on this side of the boundary.
protocol FamilyStore: Sendable {
    func currentState() async -> FamilyLinkState
    /// Publish that a strong warning was ignored here.
    func publish(_ alert: FamilyAlert) async throws
    /// Alerts received from linked peers, newest first.
    func receivedAlerts(limit: Int) async throws -> [FamilyAlert]
    /// Break every link and delete what this device published.
    func unlinkAll() async throws
    /// A pending invitation created on this device, if one exists.
    func invitationURL() async -> URL?

    // "Ask someone you trust" — the deliberate half of the feature. Separate
    // methods from the alert ones on purpose: the two carry different data under
    // different consent, and merging them would blur exactly what must stay clear.
    func ask(_ request: HelpRequest) async throws
    /// Questions others asked me.
    func incomingRequests(limit: Int) async throws -> [HelpRequest]
    /// My own questions, so I can watch for the answers.
    func myRequests(limit: Int) async throws -> [HelpRequest]
    func answer(_ request: HelpRequest, with answer: HelpRequest.Answer, as label: String) async throws
}

extension FamilyStore {
    // Most stores have no notion of invitations; only the CloudKit one does.
    func invitationURL() async -> URL? { nil }
}

/// Everything the family screen needs in one value, so the view makes a single
/// round trip instead of four.
struct FamilySnapshot: Sendable {
    var state: FamilyLinkState = .off
    var alerts: [FamilyAlert] = []
    var incoming: [HelpRequest] = []
    var mine: [HelpRequest] = []
    var invitation: URL?
}

extension FamilyStore {
    func snapshot(limit: Int = 20) async -> FamilySnapshot {
        FamilySnapshot(
            state: await currentState(),
            alerts: (try? await receivedAlerts(limit: limit)) ?? [],
            incoming: (try? await incomingRequests(limit: limit)) ?? [],
            mine: (try? await myRequests(limit: limit)) ?? [],
            invitation: await invitationURL()
        )
    }
}

/// In-memory store used by the tests and by SwiftUI previews.
actor InMemoryFamilyStore: FamilyStore {
    private var state: FamilyLinkState
    private(set) var published: [FamilyAlert] = []
    private var received: [FamilyAlert]

    init(state: FamilyLinkState = .off, received: [FamilyAlert] = []) {
        self.state = state
        self.received = received
    }

    func currentState() async -> FamilyLinkState { state }

    func publish(_ alert: FamilyAlert) async throws {
        guard state.isActive else { throw FamilyError.notLinked }
        published.append(alert)
    }

    func receivedAlerts(limit: Int) async throws -> [FamilyAlert] {
        Array(received.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }

    func unlinkAll() async throws {
        state = .off
        published.removeAll()
        received.removeAll()
        asked.removeAll()
        incoming.removeAll()
    }

    // MARK: - Help requests

    private(set) var asked: [HelpRequest] = []
    private var incoming: [HelpRequest] = []

    func seed(incoming requests: [HelpRequest]) { incoming = requests }

    func ask(_ request: HelpRequest) async throws { asked.append(request) }

    func incomingRequests(limit: Int) async throws -> [HelpRequest] {
        Array(incoming.filter { !$0.isExpired() }.sorted { $0.askedAt > $1.askedAt }.prefix(limit))
    }

    func myRequests(limit: Int) async throws -> [HelpRequest] {
        Array(asked.filter { !$0.isExpired() }.sorted { $0.askedAt > $1.askedAt }.prefix(limit))
    }

    func answer(_ request: HelpRequest, with answer: HelpRequest.Answer, as label: String) async throws {
        guard let index = incoming.firstIndex(where: { $0.id == request.id }) else {
            throw FamilyError.notLinked
        }
        incoming[index].answer = answer
        incoming[index].answeredAt = Date()
        incoming[index].answeredBy = label
    }
}

enum FamilyError: Error, Equatable {
    /// Publishing was attempted with no link set up. Never surfaced to the user
    /// as an error: nothing was expected to happen, so nothing failing is fine.
    case notLinked
    case unavailable(String)
}

/// Decides whether a verdict is worth telling a relative about.
///
/// Only an *ignored* strong warning qualifies. Not a banner, not a warning that
/// was heeded, not a page that merely looked odd. The threshold is high on
/// purpose: a relative who receives an alert every other day stops reading them,
/// and the feature becomes noise dressed as protection.
enum FamilyAlertPolicy {
    static func shouldAlert(action: VerdictAction, userContinued: Bool) -> Bool {
        action == .interstitial && userContinued
    }
}
