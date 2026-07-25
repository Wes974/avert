import Foundation
import Testing
@testable import Avert

/// The other half of the anti-drift harness (see ts/tests/l1-corpus.test.ts):
/// the same `Tests/corpus/l1.json` asserted against the Swift port. Two engines
/// implement L1 — the extension in TypeScript, the App Intent in Swift — and a
/// link must get the same reading whether it arrives by text message or is
/// opened in Safari.
struct URLHeuristicsCorpusTests {
    // Not private: `@Test(arguments:)` exposes Case in a test method signature.
    struct Corpus: Decodable {
        struct Case: Decodable {
            let url: String
            let expect: [String]
            let expectSwift: [String]?
            let note: String?
            /// What Swift must produce: the override when the divergence is
            /// declared, the common expectation otherwise.
            var expected: [String] { (expectSwift ?? expect).sorted() }
        }
        let cases: [Case]
    }

    /// Registry mirroring the entries the corpus exercises. Injected rather than
    /// `.shared`: the test bundle has no brands.json, and `.shared` would be
    /// empty — every assertion would pass for the wrong reason.
    private static let registry: [BrandEntry] = [
        BrandEntry(brand: "PayPal", aliases: [], domains: ["paypal.com"],
                   authDelegates: [], sector: "payment", region: ["GLOBAL"]),
        BrandEntry(brand: "La Banque Postale", aliases: ["Banque Postale", "LBP"],
                   domains: ["labanquepostale.fr"], authDelegates: ["*.wl-fr.com"],
                   sector: "banking", region: ["FR"]),
        BrandEntry(brand: "Amazon", aliases: [], domains: ["amazon.fr", "amazon.com"],
                   authDelegates: [], sector: "retail", region: ["GLOBAL"]),
        BrandEntry(brand: "Ameli", aliases: ["Assurance Maladie"], domains: ["ameli.fr"],
                   authDelegates: [], sector: "gov", region: ["FR"]),
        BrandEntry(brand: "Impôts", aliases: ["impots.gouv"], domains: ["impots.gouv.fr"],
                   authDelegates: ["franceconnect.gouv.fr"], sector: "gov", region: ["FR"]),
    ]

    private static let corpus: Corpus = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "l1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Corpus.self, from: data)
        else {
            fatalError("Tests/corpus/l1.json absent du bundle de test — vérifier project.yml")
        }
        return decoded
    }()

    private final class BundleToken {}

    private func keys(_ url: String) -> [String] {
        URLHeuristics.analyze(url, brands: Self.registry)
            .map { $0.id + ($0.brand.map { "@\($0)" } ?? "") }
            .sorted()
    }

    @Test("Le corpus est chargé et non vide")
    func corpusLoads() {
        #expect(Self.corpus.cases.count > 15)
    }

    @Test("Chaque cas du corpus produit les signaux attendus", arguments: corpus.cases)
    func corpusCase(_ c: Corpus.Case) {
        #expect(keys(c.url) == c.expected, "\(c.url) — \(c.note ?? "")")
    }

    @Test("Les divergences avec TypeScript sont toutes déclarées")
    func divergencesAreDeclared() {
        // If a case has no `expectSwift`, Swift must match the TS expectation
        // exactly. This is the assertion that actually prevents drift: adding a
        // rule to one engine and not the other fails here.
        for c in Self.corpus.cases where c.expectSwift == nil {
            #expect(keys(c.url) == c.expect.sorted(), "divergence non déclarée sur \(c.url)")
        }
    }
}

extension URLHeuristicsCorpusTests.Corpus.Case: CustomTestStringConvertible {
    var testDescription: String { url }
}
