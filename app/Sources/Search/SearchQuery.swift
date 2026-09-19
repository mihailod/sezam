import Foundation

/// Query preparation for the FTS5 indexes.
///
/// The index was folded at build time (Python: đ→d, Đ→D, Ł→"", Ć→C) and then
/// tokenised with `unicode61 remove_diacritics 2`. Queries MUST be folded the
/// same way. Foundation's `.diacriticInsensitive` handles č/š/ž/ć but leaves đ
/// untouched -- exactly like SQLite -- so a query for "đubre" would look for a
/// token that cannot exist in the index and silently return nothing.
enum SearchQuery {

    /// One fold for the whole app, in `SerbianLatin`. There used to be two --
    /// this one and the Users tab's -- and they drifted: the Users search
    /// indexed "Ł" that this one drops, and knew nothing of đ's spellings, so
    /// "srdjan pantic" found nobody while the Search tab found him.
    private static func foldScalar(_ ch: Character) -> String {
        String(ch).unicodeScalars.reduce(into: "") { $0 += SerbianLatin.fold(scalar: $1) }
    }

    static func fold(_ s: String) -> String { SerbianLatin.fold(s) }

    /// Folded text plus, for every folded character, the index it came from in
    /// the original string. Needed because folding is not length-preserving
    /// (Ł vanishes), so a match found in folded text cannot be applied to the
    /// original by offset alone.
    static func foldWithMap(_ s: String) -> (folded: String, map: [String.Index]) {
        var folded = ""
        var map: [String.Index] = []
        var i = s.startIndex
        while i < s.endIndex {
            for c in foldScalar(s[i]) { folded.append(c); map.append(i) }
            i = s.index(after: i)
        }
        return (folded, map)
    }

    /// Serbian đ is written three ways and the sets barely overlap: measured on
    /// the archive, "djubre" hits 588 documents and "dubre"/"đubre" hits 664,
    /// sharing only 23. No single fold catches both, so each term is expanded
    /// into an OR across spellings.
    static func variants(of term: String) -> [String] {
        var out = [term]
        if term.contains("dj") {
            out.append(term.replacingOccurrences(of: "dj", with: "d"))
        } else if term.contains("d") {
            out.append(term.replacingOccurrences(of: "d", with: "dj"))
        }
        return Array(Set(out)).sorted()
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Builds an FTS5 MATCH expression. Supports "quoted phrases", trailing *
    /// for prefix, and field scoping like author:dejanr. Everything else is
    /// treated as a literal term, so user input can never inject FTS5 syntax.
    ///
    /// The word still being typed is matched as a prefix. FTS5 otherwise
    /// matches whole words only, so live search looked up each half-typed
    /// word as if it were complete: "mihailo desp" found nothing, "despot"
    /// and "despotov" happened to be real words and briefly showed unrelated
    /// hits, and results flickered in and out until the name was finished.
    /// A trailing space means the word is done, and it matches exactly again.
    /// Two letters or fewer also stay exact -- "d*" matches 526k messages.
    static func ftsExpression(from raw: String) -> String? {
        let folded = fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else { return nil }
        let lastWordUnfinished = !(raw.last?.isWhitespace ?? true)

        var clauses: [String] = []
        var rest = Substring(folded)

        while let start = rest.firstIndex(where: { !$0.isWhitespace }) {
            rest = rest[start...]
            if rest.first == "\"" {                       // "exact phrase"
                let afterQuote = rest.index(after: rest.startIndex)
                if let close = rest[afterQuote...].firstIndex(of: "\"") {
                    let phrase = String(rest[afterQuote..<close])
                    if !phrase.isEmpty { clauses.append(quote(phrase)) }
                    rest = rest[rest.index(after: close)...]
                    continue
                }
                rest = rest[afterQuote...]                // unbalanced quote: ignore it
                continue
            }
            let end = rest.firstIndex(where: { $0.isWhitespace }) ?? rest.endIndex
            var token = String(rest[rest.startIndex..<end])
            rest = rest[end...]
            guard !token.isEmpty else { continue }

            // field:value scoping, kept as-is when the column name is known
            var column: String?
            if let colon = token.firstIndex(of: ":") {
                let name = String(token[token.startIndex..<colon])
                if ["author", "topic", "person", "body",
                    "username", "full_name", "city", "company"].contains(name) {
                    column = name
                    token = String(token[token.index(after: colon)...])
                }
            }
            guard !token.isEmpty else { continue }

            var isPrefix = token.hasSuffix("*")
            if isPrefix { token.removeLast() }
            guard !token.isEmpty else { continue }
            // `rest` is empty only after the final token, since `folded` is trimmed.
            if !isPrefix, lastWordUnfinished, rest.isEmpty, token.count >= 3 {
                isPrefix = true
            }

            let terms = variants(of: token)
                .map { quote($0) + (isPrefix ? "*" : "") }
                .joined(separator: " OR ")
            let clause = terms.contains(" OR ") ? "(\(terms))" : terms
            clauses.append(column.map { "\($0) : \(clause)" } ?? clause)
        }
        return clauses.isEmpty ? nil : clauses.joined(separator: " AND ")
    }

    /// Terms used for client-side highlighting. Contentless FTS5 returns NULL
    /// from snippet()/highlight() -- silently, with no error -- so snippets have
    /// to be built from message.body in Swift.
    static func highlightTerms(from raw: String) -> [String] {
        let folded = fold(raw)
        var terms: [String] = []
        for piece in folded.split(whereSeparator: { $0.isWhitespace || $0 == "\"" }) {
            var t = String(piece)
            if let colon = t.firstIndex(of: ":") { t = String(t[t.index(after: colon)...]) }
            if t.hasSuffix("*") { t.removeLast() }
            if t.count >= 2 { terms.append(contentsOf: variants(of: t)) }
        }
        return Array(Set(terms))
    }
}
