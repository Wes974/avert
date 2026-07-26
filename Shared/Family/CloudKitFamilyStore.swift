import CloudKit
import Foundation
import os.log

/// CloudKit implementation of `FamilyStore`.
///
/// One shared zone for the whole family, not one per person. Whoever sets it up
/// creates the zone and a `CKShare`; everyone else accepts. All participants have
/// read-write access, so the link is symmetric by construction rather than by
/// convention — there is no code path that could make it one-way, which is the
/// property the design depends on.
///
/// Deliberately thin: the rules worth testing live in `FamilyAlert` and
/// `FamilyAlertPolicy`, behind the `FamilyStore` protocol. What remains here is
/// CloudKit plumbing that cannot be tested without two devices and two iCloud
/// accounts — and is therefore kept as small and as boring as possible.
actor CloudKitFamilyStore: FamilyStore {
    private let container: CKContainer
    private let zoneID = CKRecordZone.ID(zoneName: "AvertFamily", ownerName: CKCurrentUserDefaultName)
    private static let log = Logger(subsystem: "com.ouweis.avert", category: "family")

    /// Cached across calls: resolving which database holds the zone costs a
    /// round trip, and the extension may publish while offline-ish.
    private var cachedRole: Role?

    private enum Role {
        /// We created the zone: it lives in our private database.
        case owner
        /// We accepted someone's share: it lives in our shared database.
        case participant(CKRecordZone.ID)

        var zoneID: CKRecordZone.ID? {
            if case .participant(let id) = self { return id }
            return nil
        }
    }

    init(identifier: String = "iCloud.com.ouweis.avert") {
        self.container = CKContainer(identifier: identifier)
    }

    // MARK: - State

    func currentState() async -> FamilyLinkState {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                return .unavailable(reason: Self.reason(for: status))
            }
        } catch {
            return .unavailable(reason: String(localized: "family.unavailable.icloud"))
        }

        do {
            guard let role = try await resolveRole() else { return .off }
            let peers = try await peers(for: role)
            return .linked(peers: peers)
        } catch {
            Self.log.error("family state failed: \(error.localizedDescription, privacy: .public)")
            return .unavailable(reason: String(localized: "family.unavailable.generic"))
        }
    }

    private static func reason(for status: CKAccountStatus) -> String {
        switch status {
        case .noAccount: String(localized: "family.unavailable.no-account")
        case .restricted: String(localized: "family.unavailable.restricted")
        default: String(localized: "family.unavailable.icloud")
        }
    }

    /// Where the family zone lives, if anywhere.
    private func resolveRole() async throws -> Role? {
        if let cachedRole { return cachedRole }

        // Our own zone first: the common case for whoever set the family up.
        if let zones = try? await container.privateCloudDatabase.allRecordZones(),
           zones.contains(where: { $0.zoneID.zoneName == zoneID.zoneName }) {
            cachedRole = .owner
            return .owner
        }
        // Otherwise a zone someone shared with us.
        if let shared = try? await container.sharedCloudDatabase.allRecordZones(),
           let zone = shared.first(where: { $0.zoneID.zoneName == zoneID.zoneName }) {
            let role = Role.participant(zone.zoneID)
            cachedRole = role
            return role
        }
        return nil
    }

    private func database(for role: Role) -> CKDatabase {
        switch role {
        case .owner: container.privateCloudDatabase
        case .participant: container.sharedCloudDatabase
        }
    }

    private func zone(for role: Role) -> CKRecordZone.ID {
        role.zoneID ?? zoneID
    }

    private func peers(for role: Role) async throws -> [FamilyPeer] {
        let db = database(for: role)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone(for: role))
        guard let share = try? await db.record(for: shareID) as? CKShare else { return [] }

        let me = try? await container.userRecordID()
        let iAmOwner: Bool = if case .owner = role { true } else { false }

        return share.participants.compactMap { participant in
            // Exclude myself. Comparing user record IDs is not enough on its
            // own: on the owner's device `userIdentity.userRecordID` comes back
            // nil, so `!= me` was true and I listed myself as a relative called
            // "Un proche" the instant the share was created. When we own the
            // share, the `.owner` participant *is* us — that check is reliable.
            if iAmOwner, participant.role == .owner { return nil }
            if let me, participant.userIdentity.userRecordID == me { return nil }
            // Invited but not yet accepted is not a link yet.
            guard participant.acceptanceStatus == .accepted else { return nil }
            let name = participant.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter().string(from: $0) }
            return FamilyPeer(
                id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                label: (name?.isEmpty == false ? name! : String(localized: "family.peer.unnamed")),
                lastHeardFrom: nil
            )
        }
    }

    // MARK: - Publishing

    func publish(_ alert: FamilyAlert) async throws {
        guard let role = try await resolveRole() else { throw FamilyError.notLinked }
        let record = CKRecord(
            recordType: FamilyAlert.recordType,
            recordID: CKRecord.ID(recordName: alert.id.uuidString, zoneID: zone(for: role))
        )
        // Only the allowlisted keys, straight from the type that guarantees them.
        for (key, value) in alert.recordFields { record[key] = value as CKRecordValue }
        _ = try await database(for: role).save(record)
    }

    // MARK: - Reading

    func receivedAlerts(limit: Int) async throws -> [FamilyAlert] {
        guard let role = try await resolveRole() else { return [] }
        let me = try? await container.userRecordID()

        let query = CKQuery(recordType: FamilyAlert.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "occurredAt", ascending: false)]

        let (results, _) = try await database(for: role).records(
            matching: query, inZoneWith: zone(for: role), resultsLimit: limit
        )

        return results.compactMap { recordID, result in
            guard let record = try? result.get() else { return nil }
            // Our own ignored warnings are not news to us.
            if let me, record.creatorUserRecordID == me { return nil }
            guard let id = UUID(uuidString: recordID.recordName) else { return nil }
            let fields = record.allKeys().reduce(into: [String: String]()) { acc, key in
                if let value = record[key] as? String { acc[key] = value }
            }
            return FamilyAlert(id: id, fields: fields)
        }
    }

    // MARK: - Setting up and tearing down

    /// The share URL of an invitation already created on this device, if any.
    ///
    /// Needed because the invitation has to survive leaving and reopening the
    /// screen: creating a share and then being unable to send it — which is what
    /// happened before this existed — makes the whole feature unusable.
    func invitationURL() async -> URL? {
        guard let role = try? await resolveRole(), case .owner = role else { return nil }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let record = try? await container.privateCloudDatabase.record(for: shareID),
              let share = record as? CKShare else { return nil }
        return share.url
    }

    /// Create the family zone and return a share URL to send to a relative.
    func createInvitation() async throws -> URL {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await container.privateCloudDatabase.save(zone)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = String(localized: "family.share.title") as CKRecordValue
        // Invitation only: the link must not be forwardable to strangers, and a
        // family link that anyone could join would be worse than no link.
        share.publicPermission = .none

        let saved = try await container.privateCloudDatabase.save(share)
        cachedRole = .owner
        guard let url = (saved as? CKShare)?.url else { throw FamilyError.unavailable("share URL") }
        return url
    }

    /// Leave the family: delete the zone if we own it, or remove ourselves from
    /// the share if we joined one. Either way nothing we published survives.
    func unlinkAll() async throws {
        guard let role = try await resolveRole() else { return }
        switch role {
        case .owner:
            // Deleting the zone takes the share and every record with it.
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        case .participant(let id):
            _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: id)
        }
        cachedRole = nil
    }

    /// Ask CloudKit to push when a relative publishes. Without it the feature
    /// only works while the app is open, which is not a safety feature.
    func ensureSubscription() async throws {
        guard let role = try await resolveRole() else { return }
        let id = "family-alerts"
        let db = database(for: role)
        if let existing = try? await db.subscription(for: id), existing != nil { return }

        let subscription = CKQuerySubscription(
            recordType: FamilyAlert.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        // The alert text is built on device from the record. Nothing about the
        // event travels in the push payload itself.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await db.save(subscription)
    }
}
