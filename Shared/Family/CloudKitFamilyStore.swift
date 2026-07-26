import CloudKit
import Foundation
import os.log

/// CloudKit implementation of `FamilyStore`.
///
/// **One zone per person**, not one for the family. My zone lives in my private
/// database and holds what I emit — ignored-warning alerts and help requests.
/// I share it with whoever may watch or help me. Their zones arrive in my shared
/// database, and that is where I read from.
///
/// The first version used a single family-wide zone. It could not express what
/// the feature actually needs: a parent following two children would have let
/// each child read the other's alerts, because a shared zone is shared with
/// everyone in it. Per-person zones make asymmetry the natural shape — sharing
/// my zone with you grants you nothing of yours to me — and symmetry becomes
/// simply "we both shared".
///
/// Deliberately thin: the rules worth testing live in `FamilyAlert`,
/// `HelpRequest` and `FamilyAlertPolicy`, behind the `FamilyStore` protocol.
/// What is left here cannot be tested without two devices and two iCloud
/// accounts, so it is kept small and boring.
actor CloudKitFamilyStore: FamilyStore {
    private let container: CKContainer
    /// My own outgoing zone. Always this name, in my private database.
    private let myZoneID = CKRecordZone.ID(zoneName: "AvertMe", ownerName: CKCurrentUserDefaultName)
    private static let log = Logger(subsystem: "com.ouweis.avert", category: "family")

    init(identifier: String = "iCloud.com.ouweis.avert") {
        self.container = CKContainer(identifier: identifier)
    }

    // MARK: - Account and zones

    private func accountUnavailableReason() async -> String? {
        do {
            switch try await container.accountStatus() {
            case .available: return nil
            case .noAccount: return String(localized: "family.unavailable.no-account")
            case .restricted: return String(localized: "family.unavailable.restricted")
            default: return String(localized: "family.unavailable.icloud")
            }
        } catch {
            return String(localized: "family.unavailable.icloud")
        }
    }

    private func myZoneExists() async -> Bool {
        guard let zones = try? await container.privateCloudDatabase.allRecordZones() else { return false }
        return zones.contains { $0.zoneID.zoneName == myZoneID.zoneName }
    }

    /// Zones other people shared with me — one per person I watch or help.
    private func incomingZones() async -> [CKRecordZone.ID] {
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones() else { return [] }
        return zones.map(\.zoneID)
    }

    private func share(in db: CKDatabase, zone: CKRecordZone.ID) async -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        guard let record = try? await db.record(for: id) else { return nil }
        return record as? CKShare
    }

    // MARK: - State

    func currentState() async -> FamilyLinkState {
        if let reason = await accountUnavailableReason() { return .unavailable(reason: reason) }

        let outgoing = await watchers()
        let incoming = await watched()
        let haveZone = await myZoneExists()
        guard !outgoing.isEmpty || !incoming.isEmpty || haveZone else { return .off }
        return .linked(peers: outgoing + incoming)
    }

    /// People who can see my alerts, because I shared my zone with them.
    private func watchers() async -> [FamilyPeer] {
        guard let share = await share(in: container.privateCloudDatabase, zone: myZoneID) else { return [] }
        return share.participants.compactMap { participant in
            // The `.owner` participant of my own share is me.
            guard participant.role != .owner,
                  participant.acceptanceStatus == .accepted else { return nil }
            return FamilyPeer(
                id: Self.identifier(for: participant),
                label: Self.name(for: participant),
                lastHeardFrom: nil,
                direction: .theyWatchMe
            )
        }
    }

    /// People whose alerts I can see, because they shared their zone with me.
    private func watched() async -> [FamilyPeer] {
        var peers: [FamilyPeer] = []
        for zone in await incomingZones() {
            guard let share = await share(in: container.sharedCloudDatabase, zone: zone),
                  let owner = share.participants.first(where: { $0.role == .owner })
            else { continue }
            peers.append(FamilyPeer(
                id: zone.zoneName + "/" + zone.ownerName,
                label: Self.name(for: owner),
                lastHeardFrom: nil,
                direction: .iWatchThem
            ))
        }
        return peers
    }

    private static func identifier(for participant: CKShare.Participant) -> String {
        participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString
    }

    private static func name(for participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            if !formatted.isEmpty { return formatted }
        }
        return String(localized: "family.peer.unnamed")
    }

    // MARK: - Publishing (my zone)

    func publish(_ alert: FamilyAlert) async throws {
        try await ensureMyZone()
        let record = CKRecord(
            recordType: FamilyAlert.recordType,
            recordID: CKRecord.ID(recordName: alert.id.uuidString, zoneID: myZoneID)
        )
        for (key, value) in alert.recordFields { record[key] = value as CKRecordValue }
        _ = try await container.privateCloudDatabase.save(record)
    }

    func ask(_ request: HelpRequest) async throws {
        try await ensureMyZone()
        let record = CKRecord(
            recordType: HelpRequest.recordType,
            recordID: CKRecord.ID(recordName: request.id.uuidString, zoneID: myZoneID)
        )
        for (key, value) in request.recordFields { record[key] = value as CKRecordValue }
        _ = try await container.privateCloudDatabase.save(record)
    }

    private func ensureMyZone() async throws {
        let exists = await myZoneExists()
        guard !exists else { return }
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: myZoneID))
    }

    // MARK: - Reading (their zones)

    func receivedAlerts(limit: Int) async throws -> [FamilyAlert] {
        var all: [FamilyAlert] = []
        for zone in await incomingZones() {
            let records = await fetch(FamilyAlert.recordType, in: zone, sortedBy: "occurredAt", limit: limit)
            all += records.compactMap { id, fields in
                UUID(uuidString: id.recordName).flatMap { FamilyAlert(id: $0, fields: fields) }
            }
        }
        return Array(all.sorted { $0.occurredAt > $1.occurredAt }.prefix(limit))
    }

    /// Questions other people asked me, newest first, expired ones dropped.
    func incomingRequests(limit: Int) async throws -> [HelpRequest] {
        var all: [HelpRequest] = []
        for zone in await incomingZones() {
            let records = await fetch(HelpRequest.recordType, in: zone, sortedBy: "askedAt", limit: limit)
            all += records.compactMap { id, fields in
                UUID(uuidString: id.recordName).flatMap { HelpRequest(id: $0, fields: fields) }
            }
        }
        return Array(all.filter { !$0.isExpired() }.sorted { $0.askedAt > $1.askedAt }.prefix(limit))
    }

    /// My own questions, so I can see the answers come back.
    func myRequests(limit: Int) async throws -> [HelpRequest] {
        guard await myZoneExists() else { return [] }
        let records = await fetch(HelpRequest.recordType, in: myZoneID, sortedBy: "askedAt", limit: limit, shared: false)
        return records
            .compactMap { id, fields in UUID(uuidString: id.recordName).flatMap { HelpRequest(id: $0, fields: fields) } }
            .filter { !$0.isExpired() }
            .sorted { $0.askedAt > $1.askedAt }
    }

    /// Answer someone's question, writing back into their zone.
    func answer(_ request: HelpRequest, with answer: HelpRequest.Answer, as label: String) async throws {
        for zone in await incomingZones() {
            let id = CKRecord.ID(recordName: request.id.uuidString, zoneID: zone)
            guard let record = try? await container.sharedCloudDatabase.record(for: id) else { continue }
            record["answer"] = answer.rawValue as CKRecordValue
            record["answeredAt"] = ISO8601DateFormatter().string(from: Date()) as CKRecordValue
            record["answeredBy"] = label as CKRecordValue
            _ = try await container.sharedCloudDatabase.save(record)
            return
        }
        throw FamilyError.notLinked
    }

    private func fetch(
        _ type: String, in zone: CKRecordZone.ID, sortedBy key: String, limit: Int, shared: Bool = true
    ) async -> [(CKRecord.ID, [String: String])] {
        let db = shared ? container.sharedCloudDatabase : container.privateCloudDatabase
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: key, ascending: false)]
        guard let (results, _) = try? await db.records(matching: query, inZoneWith: zone, resultsLimit: limit)
        else { return [] }

        return results.compactMap { id, result in
            guard let record = try? result.get() else { return nil }
            let fields = record.allKeys().reduce(into: [String: String]()) { acc, key in
                if let value = record[key] as? String { acc[key] = value }
            }
            return (id, fields)
        }
    }

    // MARK: - Setting up and tearing down

    func invitationURL() async -> URL? {
        guard await myZoneExists() else { return nil }
        return await share(in: container.privateCloudDatabase, zone: myZoneID)?.url
    }

    /// Create my zone and a share to send. Whoever accepts can see my alerts and
    /// answer my questions — and gets nothing of theirs shared back unless they
    /// invite me in turn. Asymmetry is the default; symmetry is two invitations.
    func createInvitation() async throws -> URL {
        try await ensureMyZone()
        if let existing = await invitationURL() { return existing }

        let share = CKShare(recordZoneID: myZoneID)
        share[CKShare.SystemFieldKey.title] = String(localized: "family.share.title") as CKRecordValue
        // Invitation only: a link anyone could join would be worse than no link.
        share.publicPermission = .none

        let saved = try await container.privateCloudDatabase.save(share)
        guard let url = (saved as? CKShare)?.url else { throw FamilyError.unavailable("share URL") }
        return url
    }

    /// Stop sharing my zone and leave everyone else's. Nothing I published survives.
    func unlinkAll() async throws {
        if await myZoneExists() {
            _ = try? await container.privateCloudDatabase.deleteRecordZone(withID: myZoneID)
        }
        for zone in await incomingZones() {
            _ = try? await container.sharedCloudDatabase.deleteRecordZone(withID: zone)
        }
    }
}
