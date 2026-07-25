import Foundation

/// L1 in Swift — a faithful port of `ts/src/l1.ts` (PLAN.md §3).
///
/// Why a second implementation of the same rules: Safari only reaches a page
/// once it is open, so the whole smishing path (a link in a text message, an
/// email, a QR code) is invisible to the extension. A link check has to run
/// outside the browser — in an App Intent and a share extension — where no
/// JavaScript exists. The alternative, shipping a JS engine to evaluate URLs in
/// Swift, costs more than 200 lines of arithmetic.
///
/// The duplication is the risk, so it is pinned down: `Tests/corpus/l1.json`
/// is read by *both* the bun tests and the Swift tests, and both must produce
/// the same signals for every entry. Divergence fails the build rather than
/// quietly making the intent disagree with the extension.
///
/// Pure: no DOM, no network, no I/O.
enum URLHeuristics {

    // MARK: - Tolerant URL parsing

    struct ParsedURL: Equatable {
        /// Lowercased, brackets kept for IPv6 (matches JS `URL.hostname`).
        let host: String
        /// Nil when absent; the string form, as JS exposes it.
        let port: String?
    }

    /// Parse just enough of a URL to run the heuristics on it.
    ///
    /// Hand-rolled rather than `URLComponents` for two reasons that both matter
    /// here. Foundation rejects or mangles hostnames containing non-ASCII, and an
    /// attacker's URL is exactly where those appear (`раypal.com`). And the
    /// userinfo trick — `https://paypal.com@evil.top/` — must resolve to
    /// `evil.top`, the way a browser does, or the check reads the wrong host and
    /// clears a hostile link.
    static func parse(_ rawURL: String) -> ParsedURL? {
        var s = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Scheme: only http(s) is in scope. `mailto:`, `javascript:`, `tel:` and
        // friends are not links to a web page and get no verdict.
        if let range = s.range(of: "://") {
            let scheme = s[s.startIndex..<range.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            s = String(s[range.upperBound...])
        } else if isNonWebScheme(s) {
            return nil
        }
        // No scheme at all is accepted: people paste `paypal-verif.top/login`
        // out of a message. Treated as https, like every mail client does.

        // Authority ends at the first path / query / fragment delimiter.
        let authorityEnd = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? s.endIndex
        var authority = String(s[s.startIndex..<authorityEnd])

        // Userinfo: everything up to the LAST "@" is credentials, not the host.
        if let at = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: at)...])
        }

        var host = authority
        var port: String?

        if host.hasPrefix("[") {
            // IPv6 literal: the port colon is the one after "]".
            guard let close = host.firstIndex(of: "]") else { return nil }
            let after = host.index(after: close)
            if after < host.endIndex, host[after] == ":" {
                port = String(host[host.index(after: after)...])
            }
            host = String(host[host.startIndex...close])
        } else if let colon = host.lastIndex(of: ":") {
            port = String(host[host.index(after: colon)...])
            host = String(host[host.startIndex..<colon])
        }

        host = host.lowercased()
        // A trailing dot is a legal FQDN form; normalise it away.
        if host.hasSuffix("."), host.count > 1 { host.removeLast() }
        guard isPlausibleHost(host) else { return nil }
        if let port, port.isEmpty || !port.allSatisfy(\.isNumber) { return nil }
        return ParsedURL(host: host, port: port)
    }

    /// Rejects anything that isn't shaped like a hostname.
    ///
    /// Without this, arbitrary shared text ("bonjour tout le monde") parsed as a
    /// host and came back with a *reassuring* verdict — worse than no answer,
    /// because the user asked about something and was told nothing was wrong.
    private static func isPlausibleHost(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            guard host.hasSuffix("]"), host.count > 2 else { return false }
            let inner = host.dropFirst().dropLast()
            return inner.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }

        // A dotless host (`localhost`, a bare word) is not a phishing target and
        // not worth a verdict. Only the intent and share paths use this parser —
        // the extension always has a real page URL.
        guard host.contains(".") else { return false }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63 else { return false }
            return label.allSatisfy { ch in
                // Non-ASCII is allowed on purpose: `pаypal.com` must reach the
                // homograph check rather than be discarded as malformed.
                ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || !ch.isASCII
            }
        }
    }

    /// A `scheme:` prefix other than http(s), with no `//` — `mailto:`,
    /// `javascript:`, `tel:`.
    ///
    /// The ambiguity to resolve is `example.com:8443/x`, whose prefix is a valid
    /// scheme charset (letters and dots). What separates them is what follows the
    /// colon: digits mean a port, anything else means a scheme. Without this,
    /// `mailto:someone@paypal.com` parsed as the host `paypal.com` and got a
    /// verdict about an address that is not a link.
    private static func isNonWebScheme(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let prefix = s[s.startIndex..<colon]
        guard let first = prefix.first, first.isLetter,
              prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }

        let afterColon = s[s.index(after: colon)...]
        let untilDelimiter = afterColon.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        // Empty or all-digits → a port, so this is `host:port`, not a scheme.
        if !untilDelimiter.isEmpty, untilDelimiter.allSatisfy(\.isNumber) { return false }
        return true
    }

    // MARK: - Punycode (RFC 3492)

    private static let punyBase = 36
    private static let punyTMin = 1
    private static let punyTMax = 26
    private static let punySkew = 38
    private static let punyDamp = 700
    private static let punyInitialBias = 72
    private static let punyInitialN = 128

    private static func punyAdapt(_ delta: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
        var delta = firstTime ? delta / punyDamp : delta >> 1
        delta += delta / numPoints
        var k = 0
        while delta > ((punyBase - punyTMin) * punyTMax) >> 1 {
            delta /= (punyBase - punyTMin)
            k += punyBase
        }
        return k + ((punyBase - punyTMin + 1) * delta) / (delta + punySkew)
    }

    /// Decode one punycode label, without the `xn--` prefix. Nil if malformed —
    /// a label we can't decode must not be silently treated as its raw form.
    static func punycodeDecode(_ input: String) -> String? {
        var output: [UInt32] = []
        var n = punyInitialN
        var i = 0
        var bias = punyInitialBias
        let chars = Array(input.unicodeScalars)

        // Everything before the last hyphen is literal ASCII.
        let lastDelim = chars.lastIndex(where: { $0 == "-" })
        if let lastDelim, lastDelim > 0 {
            for scalar in chars[0..<lastDelim] {
                guard scalar.value < 0x80 else { return nil }
                output.append(scalar.value)
            }
        }

        var idx = (lastDelim.map { $0 > 0 ? $0 + 1 : 0 }) ?? 0
        while idx < chars.count {
            let oldi = i
            var w = 1
            var k = punyBase
            while true {
                guard idx < chars.count else { return nil }
                let cp = Int(chars[idx].value)
                idx += 1
                let digit: Int
                if cp >= 0x61 { digit = cp - 0x61 }        // a-z
                else if cp >= 0x41 { digit = cp - 0x41 }   // A-Z
                else if cp >= 0x30 { digit = cp - 0x30 + 26 } // 0-9
                else { return nil }
                guard digit >= 0, digit < punyBase else { return nil }
                // Overflow guard: a crafted label must not trap the process.
                let (mul, mulOverflow) = digit.multipliedReportingOverflow(by: w)
                guard !mulOverflow else { return nil }
                let (sum, addOverflow) = i.addingReportingOverflow(mul)
                guard !addOverflow else { return nil }
                i = sum

                let t = k <= bias ? punyTMin : (k >= bias + punyTMax ? punyTMax : k - bias)
                if digit < t { break }
                let (nextW, wOverflow) = w.multipliedReportingOverflow(by: punyBase - t)
                guard !wOverflow else { return nil }
                w = nextW
                k += punyBase
            }
            bias = punyAdapt(i - oldi, output.count + 1, oldi == 0)
            let (nextN, nOverflow) = n.addingReportingOverflow(i / (output.count + 1))
            guard !nOverflow else { return nil }
            n = nextN
            i %= output.count + 1
            guard n <= 0x10FFFF, let scalar = Unicode.Scalar(UInt32(n)), scalar.value != 0 else { return nil }
            output.insert(scalar.value, at: i)
            i += 1
        }

        var result = ""
        for value in output {
            guard let scalar = Unicode.Scalar(value) else { return nil }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    // MARK: - Script mixing & confusables

    static func hasMixedScript(_ label: String) -> Bool {
        var cyrillic = false, greek = false, latin = false
        for scalar in label.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: cyrillic = true
            case 0x0370...0x03FF: greek = true
            case 0x41...0x5A, 0x61...0x7A: latin = true
            default: break
            }
        }
        return [cyrillic, greek, latin].filter { $0 }.count > 1
    }

    /// Homoglyphs → ASCII. Deliberately small: only glyphs that are visually
    /// near-identical in an address bar. Mirrors CONFUSABLES in l1.ts.
    static let confusables: [Character: Character] = [
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y",
        "і": "i", "ѕ": "s", "ԁ": "d", "ј": "j", "һ": "h", "ԛ": "q", "ԝ": "w",
        "ο": "o", "α": "a", "ν": "v", "ι": "i", "κ": "k", "τ": "t", "υ": "u",
        "0": "o", "1": "l", "3": "e", "5": "s", "7": "t",
    ]

    static func normalizeConfusables(_ s: String) -> String {
        String(s.map { confusables[$0] ?? $0 })
    }

    // MARK: - Levenshtein with cutoff

    static func levenshtein(_ a: String, _ b: String, cutoff: Int) -> Int {
        let lhs = Array(a), rhs = Array(b)
        if abs(lhs.count - rhs.count) > cutoff { return cutoff + 1 }
        if lhs.isEmpty { return rhs.count > cutoff ? cutoff + 1 : rhs.count }
        if rhs.isEmpty { return lhs.count > cutoff ? cutoff + 1 : lhs.count }

        var prev = Array(0...rhs.count)
        for i in 1...lhs.count {
            var cur = [i]
            var rowMin = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                let v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                cur.append(v)
                rowMin = min(rowMin, v)
            }
            if rowMin > cutoff { return cutoff + 1 }
            prev = cur
        }
        return prev[rhs.count]
    }

    // MARK: - Registry-independent tables (mirror l1.ts)

    static let lowRepTLDs: Set<String> = [
        "top", "xyz", "tk", "ml", "ga", "cf", "gq", "icu", "click", "link",
        "work", "rest", "fit", "loan", "men", "bid", "stream", "racing", "win",
        "party", "date", "faith", "review", "vip", "monster", "quest", "cyou",
    ]

    static let comboKeywords = [
        "secure", "verif", "verification", "login", "signin", "sign-in", "account",
        "support", "update", "confirm", "wallet", "service", "auth", "id",
        "assistance", "client", "portail", "espace",
    ]

    /// Tokens that identify a brand inside a domain: the SLD of each brand
    /// domain. Short ones (< 4 chars) are excluded — "id", "sg" would match
    /// half the web.
    static func brandTokens(_ brand: BrandEntry) -> [String] {
        var tokens = Set<String>()
        for domain in brand.domains {
            let sld = BrandRegistry.registrableDomain(domain).split(separator: ".").first.map(String.init) ?? ""
            if sld.count >= 4 { tokens.insert(sld) }
        }
        return Array(tokens).sorted()
    }

    private static func isOwned(host: String, by brand: BrandEntry) -> Bool {
        let reg = BrandRegistry.registrableDomain(host)
        if brand.domains.contains(where: { BrandRegistry.registrableDomain($0) == reg }) { return true }
        return brand.authDelegates.contains { delegate in
            let clean = delegate.hasPrefix("*.") ? String(delegate.dropFirst(2)) : delegate
            return BrandRegistry.registrableDomain(clean) == reg || host == clean
        }
    }

    // MARK: - Analysis

    static func analyze(_ rawURL: String, brands: [BrandEntry]) -> [L1Signal] {
        guard let parsed = parse(rawURL) else { return [] }
        let host = parsed.host
        let labels = host.split(separator: ".").map(String.init)
        let reg = BrandRegistry.registrableDomain(host)
        let sld = reg.split(separator: ".").first.map(String.init) ?? ""
        let tld = labels.last ?? ""

        // A domain a registry brand actually owns has nothing to answer for —
        // this is the main false-positive guard on legitimate sites.
        if brands.contains(where: { isOwned(host: host, by: $0) }) { return [] }

        var signals: [L1Signal] = []

        // --- Structure
        if isIPv4Literal(host) || host.hasPrefix("[") {
            signals.append(L1Signal(id: "l1.ip-literal", detail: host, brand: nil))
        }
        if let port = parsed.port, port != "80", port != "443" {
            signals.append(L1Signal(id: "l1.exotic-port", detail: port, brand: nil))
        }
        if labels.count >= 5 {
            signals.append(L1Signal(id: "l1.subdomain-depth", detail: String(labels.count), brand: nil))
        }
        if lowRepTLDs.contains(tld) {
            signals.append(L1Signal(id: "l1.low-rep-tld", detail: tld, brand: nil))
        }

        // --- IDN / punycode / homographs
        //
        // Divergence from the TS side, deliberate: JavaScript's `URL` silently
        // IDNA-encodes a Unicode hostname, so l1.ts only ever sees `xn--` forms.
        // Here the raw string is whatever the user pasted, so both shapes occur —
        // `xn--pypal-4ve.com` and `pаypal.com` must behave the same. Only the
        // `l1.punycode` signal distinguishes them, which is correct: it reports
        // the *encoding*, and the analysis runs on the decoded form either way.
        let decodedLabels = labels.map { label -> String in
            guard label.hasPrefix("xn--") else { return label }
            return punycodeDecode(String(label.dropFirst(4))) ?? label
        }
        if labels.contains(where: { $0.hasPrefix("xn--") }) {
            signals.append(L1Signal(id: "l1.punycode", detail: decodedLabels.joined(separator: "."), brand: nil))
        }
        let decodedHost = decodedLabels.joined(separator: ".")
        if decodedLabels.contains(where: hasMixedScript) {
            signals.append(L1Signal(id: "l1.mixed-script", detail: decodedHost, brand: nil))
        }

        // --- Brand-implicating signals
        let decodedSLD = BrandRegistry.registrableDomain(decodedHost)
            .split(separator: ".").first.map(String.init) ?? sld
        let normalizedSLD = normalizeConfusables(decodedSLD)
        let subLabels = decodedLabels.dropLast(reg.split(separator: ".").count)

        for brand in brands {
            for token in brandTokens(brand) {
                // Homograph: after folding, the SLD *is* the brand token.
                if normalizedSLD == token && sld != token {
                    signals.append(L1Signal(id: "l1.homograph", detail: "\(sld) → \(token)", brand: brand.brand))
                    continue
                }
                // Typosquat: small edit distance.
                let maxDist = token.count >= 8 ? 2 : 1
                let dist = levenshtein(normalizedSLD, token, cutoff: maxDist)
                if dist > 0 && dist <= maxDist {
                    signals.append(L1Signal(id: "l1.typosquat", detail: "\(sld) ≈ \(token)", brand: brand.brand))
                    continue
                }
                // Combosquat: brand token embedded with a lure keyword or a hyphen.
                if normalizedSLD != token, normalizedSLD.contains(token) {
                    let rest = normalizedSLD.replacingOccurrences(of: token, with: "")
                    let luring = comboKeywords.contains(where: { normalizedSLD.contains($0) }) || rest.contains("-")
                    if luring {
                        signals.append(L1Signal(id: "l1.combosquat", detail: sld, brand: brand.brand))
                        continue
                    }
                }
                // Brand as a subdomain of a foreign domain: paypal.com.evil.xyz.
                if subLabels.contains(where: { normalizeConfusables($0).contains(token) }) {
                    signals.append(L1Signal(id: "l1.brand-subdomain", detail: host, brand: brand.brand))
                }
            }
        }

        // Dedup identical (id, brand) pairs, preserving order.
        var seen = Set<String>()
        return signals.filter { signal in
            let key = "\(signal.id)|\(signal.brand ?? "")"
            return seen.insert(key).inserted
        }
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isNumber)
        }
    }
}
