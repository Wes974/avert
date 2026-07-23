import Foundation

/// Cumulative scoring engine (PLAN.md §5). M0: stub that proves the
/// dossier → verdict path; weights and identity multiplier land in M2/M3.
struct ScoreEngine {
    func evaluate(_ dossier: PageDossier) -> Verdict {
        Verdict(
            action: .silent,
            score: 0,
            reason: nil,
            echoHost: dossier.host
        )
    }
}
