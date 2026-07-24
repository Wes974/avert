import SafariServices
import os.log

/// Wrapper so the non-Sendable NSExtensionContext can cross into the Task
/// that runs the async L3 path. Safe: the context is only touched once, to
/// complete the request.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

/// Receives native messages from the extension's background script.
/// On iOS this runs in the app-extension process — the whole engine
/// (registry, scoring, FoundationModels) is called from here.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let log = Logger(subsystem: "com.ouweis.impostor", category: "native")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let ctx = UncheckedSendable(value: context)

        switch message?["type"] as? String {
        case "dossier":
            // Serialize to Data before crossing into the Task: [String: Any]
            // is not Sendable, Data is. The whole async leg lives in one
            // function — inlining the await+complete in the Task closure trips
            // a Swift 6 region-isolation checker bug (Xcode 26.5).
            let rawData = (message?["dossier"] as? [String: Any])
                .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            Task { await Self.respondToDossier(rawData, ctx) }
        case "jsError":
            let detail = (message?["detail"] as? String) ?? "?"
            Self.log.error("content script error: \(detail, privacy: .public)")
            Self.complete(ctx, with: ["ok": true])
        case "ack":
            // Second leg of the round-trip proof: JS confirming it received
            // our verdict. Log only.
            let host = (message?["echoHost"] as? String) ?? "?"
            Self.log.info("round-trip ack from JS for host \(host, privacy: .public)")
            Self.complete(ctx, with: ["ok": true])
        default:
            Self.log.error("unknown native message type")
            Self.complete(ctx, with: ["error": "unknown message type"])
        }
    }

    private static func respondToDossier(_ rawData: Data?, _ ctx: UncheckedSendable<NSExtensionContext>) async {
        let payload = await handleDossier(rawData)
        complete(ctx, with: payload)
    }

    private static func complete(_ ctx: UncheckedSendable<NSExtensionContext>, with payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        ctx.value.completeRequest(returningItems: [response])
    }

    private static func handleDossier(_ raw: Data?) async -> [String: Any] {
        // Defensive parsing: JS input is untrusted by construction.
        guard let data = raw,
              let dossier = try? JSONDecoder().decode(PageDossier.self, from: data)
        else {
            log.error("dossier failed to decode")
            return ["error": "bad dossier"]
        }

        let l1Ids = dossier.l1Signals.map(\.id).joined(separator: ",")
        log.info("dossier received: host=\(dossier.host, privacy: .public) capturePoints=\(dossier.capturePoints.count) l1=[\(l1Ids, privacy: .public)]")

        let engine = ScoreEngine()
        let signalMismatch = ScoreEngine.signalIdentityMismatch(dossier)

        // Opt-in novelty signal (off by default). Look up before recording so
        // the first visit counts as unseen.
        let domain = BrandRegistry.registrableDomain(dossier.host)
        let unseen = LoginHistoryStore.shared.hasSeen(domain: domain) == false
        LoginHistoryStore.shared.record(domain: domain)

        var verdict = engine.evaluate(dossier, identityMismatch: signalMismatch, unseenLoginDomain: unseen)

        // Bring-up diagnostic (removed in M6): surfaces L3 state on-screen
        // because os_log .info doesn't reach idevicesyslog.
        var l3Debug = signalMismatch ? "l3=off(signals already mismatch)" : "l3=off(score<\(ScoreEngine.l3WakeThreshold))"

        // L3 gate: wake the model (~2.3 s) only when it can still change the
        // outcome — i.e. the page is suspicious enough (score ≥ threshold) AND
        // the URL/DOM signals haven't already proven the identity mismatch.
        // If they have, the verdict already reflects it and L3 is pure cost.
        if !signalMismatch, verdict.score >= ScoreEngine.l3WakeThreshold {
            let t0 = Date()
            if let extraction = await L3Extractor.extract(from: dossier) {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let l3Mismatch = extraction.confidence >= 0.6
                    && BrandRegistry.shared.identityMismatch(
                        claimedBrand: extraction.claimedBrand,
                        host: dossier.host
                    )
                verdict = engine.evaluate(
                    dossier,
                    identityMismatch: signalMismatch || l3Mismatch,
                    l3: extraction,
                    unseenLoginDomain: unseen
                )
                let brand = extraction.claimedBrand.isEmpty ? "∅" : extraction.claimedBrand
                l3Debug = "l3=OK \(ms)ms in=\(dossier.title.count)/\(dossier.textExcerpt.count)c brand=\(brand) conf=\(String(format: "%.2f", extraction.confidence)) intent=\(extraction.pageIntent) mismatch=\(l3Mismatch)"
            } else {
                let why = L3Extractor.lastFailure ?? "modèle indisponible (Apple Intelligence off ?)"
                l3Debug = "l3=failed: \(why)"
            }
        }

        log.info("verdict: action=\(verdict.action.rawValue, privacy: .public) score=\(verdict.score) \(l3Debug, privacy: .public)")

        guard let verdictData = try? JSONEncoder().encode(verdict),
              var verdictDict = try? JSONSerialization.jsonObject(with: verdictData) as? [String: Any]
        else {
            return ["error": "verdict encoding failed"]
        }
        // The on-screen diagnostic ships only in debug builds; release verdicts
        // never carry it, so the banner/interstitial stay clean.
        #if DEBUG
        verdictDict["debug"] = "score=\(verdict.score) · \(l3Debug)"
        #endif
        return ["type": "verdict", "verdict": verdictDict]
    }
}
