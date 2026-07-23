import SafariServices
import os.log

/// Receives native messages from the extension's background script.
/// On iOS this runs in the app-extension process — the whole engine
/// (registry, scoring, later FoundationModels) is called from here.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let log = Logger(subsystem: "com.ouweis.impostor", category: "native")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        let responsePayload: [String: Any]
        switch message?["type"] as? String {
        case "dossier":
            responsePayload = handleDossier(message?["dossier"])
        case "jsError":
            let detail = (message?["detail"] as? String) ?? "?"
            Self.log.error("content script error: \(detail, privacy: .public)")
            responsePayload = ["ok": true]
        case "ack":
            // Second leg of the M0 round-trip proof: JS confirming it received
            // our verdict. Log only, empty response.
            let host = (message?["echoHost"] as? String) ?? "?"
            Self.log.info("round-trip ack from JS for host \(host, privacy: .public)")
            responsePayload = ["ok": true]
        default:
            Self.log.error("unknown native message type")
            responsePayload = ["error": "unknown message type"]
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: responsePayload]
        context.completeRequest(returningItems: [response])
    }

    private func handleDossier(_ raw: Any?) -> [String: Any] {
        // Defensive parsing: JS input is untrusted by construction.
        guard let dict = raw as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let dossier = try? JSONDecoder().decode(PageDossier.self, from: data)
        else {
            Self.log.error("dossier failed to decode")
            return ["error": "bad dossier"]
        }

        let signalIds = dossier.l1Signals.map(\.id).joined(separator: ",")
        Self.log.info("dossier received: host=\(dossier.host, privacy: .public) capturePoints=\(dossier.capturePoints.count) l1=[\(signalIds, privacy: .public)]")

        let verdict = ScoreEngine().evaluate(dossier)
        guard let verdictData = try? JSONEncoder().encode(verdict),
              let verdictDict = try? JSONSerialization.jsonObject(with: verdictData) as? [String: Any]
        else {
            return ["error": "verdict encoding failed"]
        }
        return ["type": "verdict", "verdict": verdictDict]
    }
}
