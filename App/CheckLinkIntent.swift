import AppIntents
import SwiftUI

/// "Vérifier ce lien" — Siri, Spotlight, Shortcuts, and the Action button.
///
/// Closes the biggest gap in the product: Safari only reaches a page once it is
/// open, so a link in a text message is invisible to the extension until the
/// damage is one tap away. This checks the address *before* opening it.
///
/// It runs entirely in-process: the same brand registry, the same L1 rules as
/// the extension (`URLHeuristics`, pinned to the TS engine by
/// `Tests/corpus/l1.json`). No network, consistent with everything else.
struct CheckLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Vérifier ce lien"
    static var description = IntentDescription(
        "Analyse une adresse web sans l'ouvrir : caractères trompeurs, marque imitée, structure inhabituelle. Tout se passe sur l'appareil.",
        categoryName: "Sécurité"
    )

    /// No confirmation step and no app launch: the answer is the point, and
    /// opening the app to read it would defeat a check meant to happen *before*
    /// touching the link.
    static var openAppWhenRun = false

    @Parameter(
        title: "Lien",
        description: "L'adresse à vérifier.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var link: String

    static var parameterSummary: some ParameterSummary {
        Summary("Vérifier \(\.$link)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let result = LinkChecker.check(link) else {
            return .result(
                dialog: IntentDialog(stringLiteral: String(localized: "link.error.not-a-link")),
                view: LinkCheckSnippet(notALink: link)
            )
        }
        // The spoken answer keeps the caveat: Siri reading "nothing unusual" with
        // no qualifier would be exactly the false reassurance the app refuses to
        // give anywhere else.
        let spoken = "\(result.headline). \(result.explanation) \(result.caveat)"
        return .result(
            dialog: IntentDialog(stringLiteral: spoken),
            view: LinkCheckSnippet(check: result)
        )
    }
}

/// Exposes the intent to Siri and Spotlight without the user building a
/// shortcut. Phrases must contain the app name — App Intents requires it.
struct AvertShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckLinkIntent(),
            phrases: [
                "Vérifier ce lien avec \(.applicationName)",
                "Analyser ce lien avec \(.applicationName)",
                "Check this link with \(.applicationName)",
            ],
            shortTitle: "Vérifier ce lien",
            systemImageName: "link.badge.plus"
        )
    }
}
