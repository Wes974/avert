import Foundation

/// What a relative learns when a strong warning is ignored on a linked device.
///
/// The product decision (2026-07-26) is that they learn **that** it happened and
/// nothing else: not the site, not the brand, not the address. This type is the
/// enforcement of that decision, not a description of it — there is no field
/// here that could carry a destination, so there is nothing to leak, forget to
/// strip, or accidentally log.
///
/// The distinction matters more than it looks. "A warning was ignored at 21:04
/// on Papa's iPhone" is a safety signal. "Papa visited paypal-verif.top at
/// 21:04" is a browsing log. The second is a different product, one this app
/// refuses to be — and refusing it in the type system is the only refusal that
/// survives future edits.
///
/// This is also the first and only thing Avert ever sends off the device, and
/// only for people who deliberately turn it on. `FamilyLinkView` says so
/// plainly; the Privacy section must never claim otherwise.
struct FamilyAlert: Identifiable, Equatable, Sendable {
    /// Stable identity, generated on the sending device.
    let id: UUID
    /// When the warning was ignored. Second precision is plenty and rounding
    /// away sub-second detail removes a needless correlation handle.
    let occurredAt: Date
    /// How the sender chose to be known — free text they typed, e.g. "iPhone de
    /// Papa". Never derived from the device name, which often carries a full
    /// legal name the user never chose to publish.
    let deviceLabel: String

    init(id: UUID = UUID(), occurredAt: Date, deviceLabel: String) {
        self.id = id
        self.occurredAt = Date(timeIntervalSince1970: occurredAt.timeIntervalSince1970.rounded())
        self.deviceLabel = String(deviceLabel.prefix(Self.maxLabelLength))
    }

    /// Long enough for "iPhone de grand-mère", short enough that the field can't
    /// be repurposed to smuggle a URL.
    static let maxLabelLength = 40
}

// MARK: - Wire format

extension FamilyAlert {
    /// The exact set of keys that may ever be written to CloudKit.
    ///
    /// Declared as data, and asserted by `FamilyAlertTests`, so that adding a
    /// field to this type without thinking breaks a test instead of quietly
    /// widening what gets sent. The allowlist is the promise.
    static let recordKeys: Set<String> = ["occurredAt", "deviceLabel"]

    static let recordType = "FamilyAlert"

    /// Field dictionary for the CloudKit record. Deliberately built by hand
    /// rather than by reflection or `Codable`: a synthesised encoder would pick
    /// up whatever fields a future edit adds, which is precisely the failure
    /// this design exists to prevent.
    var recordFields: [String: String] {
        [
            "occurredAt": ISO8601DateFormatter().string(from: occurredAt),
            "deviceLabel": deviceLabel,
        ]
    }

    init?(id: UUID, fields: [String: String]) {
        guard let raw = fields["occurredAt"],
              let date = ISO8601DateFormatter().date(from: raw)
        else { return nil }
        self.init(id: id, occurredAt: date, deviceLabel: fields["deviceLabel"] ?? "")
    }
}

// MARK: - Wording

extension FamilyAlert {
    /// What the relative actually reads. Notice what it does not offer: any
    /// affordance to find out where. There is nothing more to show.
    func message(relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: occurredAt, relativeTo: now)
        return String(format: String(localized: "family.alert.message"), deviceLabel, when)
    }
}
