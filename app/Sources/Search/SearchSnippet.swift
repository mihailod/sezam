import SwiftUI

/// Contentless FTS5 returns NULL from snippet() and highlight() -- with no
/// error -- so excerpts are produced here from the stored body.
enum SearchSnippet {
    static func make(from body: String, terms: [String], window: Int = 180) -> AttributedString {
        let clean = body.replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
        let (folded, map) = SearchQuery.foldWithMap(clean)

        // First match wins; terms are already folded and lowercased.
        var hit: Range<String.Index>?
        for term in terms.sorted(by: { $0.count > $1.count }) {
            if let r = folded.range(of: term) { hit = r; break }
        }

        guard let hit,
              let matchLo = map[safe: folded.distance(from: folded.startIndex, to: hit.lowerBound)],
              let hiIdx = map[safe: folded.distance(from: folded.startIndex, to: hit.upperBound) - 1]
        else {
            return AttributedString(String(clean.prefix(window))
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Widen to whole words: a prefix search for "desp" should light up
        // "Despotović", not a four-letter fragment of it.
        var lo = matchLo
        var hi = clean.index(after: hiIdx)
        while lo > clean.startIndex {
            let prev = clean.index(before: lo)
            guard clean[prev].isLetter || clean[prev].isNumber else { break }
            lo = prev
        }
        while hi < clean.endIndex, clean[hi].isLetter || clean[hi].isNumber {
            hi = clean.index(after: hi)
        }

        let before = clean.index(lo, offsetBy: -window / 2, limitedBy: clean.startIndex) ?? clean.startIndex
        let after  = clean.index(hi, offsetBy: window / 2, limitedBy: clean.endIndex) ?? clean.endIndex

        var result = AttributedString()
        if before > clean.startIndex { result += AttributedString("…") }
        result += AttributedString(String(clean[before..<lo])
                    .replacingOccurrences(of: "\n", with: " "))
        var match = AttributedString(String(clean[lo..<hi]))
        match.inlinePresentationIntent = .stronglyEmphasized
        match.foregroundColor = .accentColor
        result += match
        result += AttributedString(String(clean[hi..<after])
                    .replacingOccurrences(of: "\n", with: " "))
        if after < clean.endIndex { result += AttributedString("…") }
        return result
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
