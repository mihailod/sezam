import Foundation

/// Collation for the Serbian Latin alphabet (abeceda):
///
///     A B C Č Ć D Đ E F G H I J K L M N O P R S Š T U V Z Ž
///
/// Foundation sorts these the English way. It treats Č as a decorated C, and
/// once the diacritic is the only thing left to compare it orders the decorated
/// form after every undecorated one -- so Čolić lands past Zorić instead of
/// directly after Cvetković, and Šarić past Žikić instead of after Simić. Č Ć Š
/// Ž Đ are not decorated letters here, they are letters, each with a fixed
/// place in the alphabet.
///
/// Two deliberate departures from the strict abeceda:
///
/// * The digraphs Dž, Lj and Nj are **not** treated as single letters. Strictly
///   they are, and a Serbian dictionary files Ljubomir under "Lj" -- but a
///   reader scanning an index for "L" does not expect every Lj- name to be
///   missing from it. They sort as D+ž, L+j, N+j instead.
/// * Q, W, X and Y are not in the abeceda at all. They keep their usual Latin
///   positions so foreign names still land somewhere predictable.
enum SerbianLatin {

    /// Alphabet order. Index in this array *is* the sort weight.
    static let alphabet: [Character] =
        ["a", "b", "c", "č", "ć", "d", "đ", "e", "f", "g", "h", "i", "j", "k",
         "l", "m", "n", "o", "p", "q", "r", "s", "š", "t", "u", "v", "w", "x",
         "y", "z", "ž"]

    private static let weight: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() { m[c] = i }
        return m
    }()

    /// Character classes, ordered: whitespace < digits < letters. Anything else
    /// (punctuation, symbols) is skipped entirely, so "Bit - Software" and
    /// "Bit Software" sort together instead of being separated by the dash.
    private static let classSpace = "0"
    private static let classDigit = "1"
    private static let classLetter = "2"

    /// Sort key: compare these with `<` to get Serbian order.
    ///
    /// Every source character becomes three ASCII characters -- a class digit
    /// and a two-digit weight -- so the result is pure ASCII and its ordering
    /// is plain lexicographic, with none of the normalisation subtleties that
    /// comparing the original strings would bring back in.
    static func key(_ s: String) -> String {
        // macOS hands back NFD from the filesystem and NFC from HTML; compose
        // first so "č" is one character to look up rather than c + U+030C.
        let src = s.precomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        out.reserveCapacity(src.count * 3)
        // Runs of whitespace collapse to one separator, and a leading one is
        // dropped. Without this, removing the dash from "Bit - Software" would
        // leave two separators where "Bit Software" has one, and the two would
        // no longer sort together -- which is the whole point of dropping it.
        var pendingSpace = false
        for ch in src {
            if let w = weight[ch] {
                if pendingSpace, !out.isEmpty { out += classSpace + "00" }
                pendingSpace = false
                out += classLetter + Self.pad(w)
            } else if let d = ch.wholeNumberValue, ch.isNumber, (0...9).contains(d) {
                if pendingSpace, !out.isEmpty { out += classSpace + "00" }
                pendingSpace = false
                out += classDigit + Self.pad(d)
            } else if ch.isWhitespace {
                pendingSpace = true
            } else if ch.isLetter {
                // A letter outside the abeceda (é, ü, ß...). Fold it to ASCII
                // and weigh whatever that produces, so it still sorts near the
                // letter a reader would look under.
                for f in SearchQuery.fold(String(ch)).lowercased() {
                    if let w = weight[f] {
                        if pendingSpace, !out.isEmpty { out += classSpace + "00" }
                        pendingSpace = false
                        out += classLetter + Self.pad(w)
                    }
                }
            }
        }
        return out
    }

    private static func pad(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    /// Uppercase section letter for the index bar: "Č", "Š", "Ž" are their own
    /// sections, not lumped under C, S and Z. Anything not starting with a
    /// letter of the alphabet lands in "#".
    static func bucket(_ s: String) -> String {
        let src = s.precomposedStringWithCanonicalMapping.lowercased()
        guard let first = src.first(where: { !$0.isWhitespace }) else { return "#" }
        if let c = normalized(first) { return String(c).uppercased() }
        return "#"
    }

    /// Position of a bucket letter in the alphabet, for ordering sections.
    /// Sorting the letters themselves as strings would put "Č" after "Z" again.
    static func bucketOrder(_ bucket: String) -> Int {
        guard let c = bucket.lowercased().first, let w = weight[c] else { return 0 }
        return w
    }

    private static func normalized(_ ch: Character) -> Character? {
        if weight[ch] != nil { return ch }
        guard ch.isLetter else { return nil }
        return SerbianLatin.alphabet.first { SearchQuery.fold(String(ch)).lowercased().first == $0 }
    }
}
