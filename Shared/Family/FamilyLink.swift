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
    let id: String
    /// How they chose to be known. Their label, not one we assigned.
    let label: String
    /// When we last received anything from them. Nil means never — worth
    /// showing, because a link that has gone quiet may simply be broken, and a
    /// safety feature that has silently stopped working is worse than none.
    let lastHeardFrom: Date?
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
