import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Share-sheet entry point: "Vérifier ce lien".
///
/// This is the path that actually matters for smishing. A phishing text message
/// is read in Messages, and the only safe move there is long-press → share →
/// check, *before* the link opens. An App Intent alone wouldn't cover it: the
/// share sheet is where the user already is.
///
/// Registered as an **action** extension (`com.apple.ui-services`), not a share
/// extension. Both appear in the same sheet but in different places: a share
/// extension sits in the top row of app icons, where the user has to recognise
/// and pick "Avert" among every app that accepts a link; an action extension
/// sits in the actions list underneath, reading as the verb it is —
/// "Vérifier ce lien". For a check you run on a link you already distrust, the
/// verb is what you look for, not the app name.
///
/// Extracts the URL from the attachments, runs the same engine as everything
/// else, shows the verdict. No network, and the link is never opened.
final class LinkActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { @MainActor in
            let input = await extractLink()
            present(input)
        }
    }

    // MARK: - Input

    /// The shared item, as a string. Accepts a URL attachment or plain text —
    /// Messages hands over one or the other depending on how the user selected
    /// it, and a link pasted as text is the common case.
    private func extractLink() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return url.absoluteString
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    // A message body rather than a bare link: pull the first
                    // URL-looking token out of it.
                    return firstLink(in: text) ?? text
                }
            }
        }
        return nil
    }

    /// First http(s) token, or the first host-looking token. Scans text the user
    /// shared — a lure message is usually a sentence wrapped around one link.
    private func firstLink(in text: String) -> String? {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).map(String.init)
        if let explicit = tokens.first(where: { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }) {
            return explicit
        }
        return tokens.first { token in
            token.contains(".") && !token.contains("@") && URLHeuristics.parse(token) != nil
        }
    }

    // MARK: - Output

    @MainActor
    private func present(_ input: String?) {
        let content: AnyView
        if let input, let check = LinkChecker.check(input) {
            content = AnyView(LinkCheckSnippet(check: check))
        } else {
            content = AnyView(LinkCheckSnippet(notALink: input ?? ""))
        }

        let root = ActionSheet(content: content) { [weak self] in
            // Always `completeRequest`, never `cancelRequest`: the user asked for
            // an opinion and got one — this isn't a failure.
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Chrome around the verdict: a title, the result, one way out.
private struct ActionSheet: View {
    let content: AnyView
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(16)
            }
            .background(MidnightGround())
            .navigationTitle("Avert")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: done)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.avertIndigo)
    }
}
