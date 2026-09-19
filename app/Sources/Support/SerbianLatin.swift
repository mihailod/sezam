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
                for f in fold(String(ch)) {
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

    /// Latin letters with marks, mapped to bare ASCII. Built once, from the
    /// Unicode data rather than by hand: every scalar in Latin-1 Supplement
    /// and Latin Extended-A is decomposed and stripped of its combining marks.
    ///
    /// A `static let` is initialised lazily and exactly once, so the ~380
    /// decompositions here happen on whichever thread asks first and never
    /// again -- which is the entire point, since doing this work per string is
    /// what made the search index take 1.4 seconds to build.
    private static let asciiByScalar: [UnicodeScalar: String] = {
        var m: [UnicodeScalar: String] = [:]
        for v in 0xC0...0x17F {
            guard let u = UnicodeScalar(v) else { continue }
            let bare = String(u).decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { !(0x300...0x36F).contains($0.value) }
            m[u] = String(String.UnicodeScalarView(bare)).lowercased()
        }
        // Stroked and slashed letters have no canonical decomposition -- the
        // stroke is part of the letter, not an accent on it -- so Unicode
        // cannot answer for these and they are named outright.
        m["đ"] = "d"; m["Đ"] = "d"
        m["ø"] = "o"; m["Ø"] = "o"
        // CP852 quote-prefix mojibake. The message index drops it at build
        // time, so text folded here has to drop it too, or the two disagree.
        m["ł"] = ""; m["Ł"] = ""
        return m
    }()

    /// Folds text for substring searching: lower case, marks removed, so
    /// "ristanovic" matches "Ristanović" and "muller" matches "Müller".
    ///
    /// Deliberately scalar by scalar with an ASCII fast path. The obvious
    /// spelling -- `precomposedStringWithCanonicalMapping`, then
    /// `folding(options: .diacriticInsensitive)` -- is four ICU calls per
    /// string, and over 8,188 members that measured 1,356 ms on the first tap
    /// of the Users tab. This does the same job in a fraction of that, because
    /// the only ICU work left happened once, in the table above.
    static func fold(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for u in s.unicodeScalars { out += fold(scalar: u) }
        return out
    }

    /// One scalar folded. Exposed because the search snippet has to map a match
    /// in folded text back to the original, which needs the pieces separately.
    static func fold(scalar u: UnicodeScalar) -> String {
        switch u.value {
        case 0x41...0x5A:                       // A-Z
            return String(UnicodeScalar(u.value + 32)!)
        case 0x00...0x7F:                       // the rest of ASCII, as-is
            return String(u)
        case 0x300...0x36F:                     // a combining mark: drop it
            return ""
        default:
            // Anything the table does not cover -- Cyrillic, Latin Extended-B,
            // the rarer accents -- folded by ICU, the same call the message
            // index's queries used before both sides shared this function.
            return asciiByScalar[u] ?? String(u).folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US"))
        }
    }

    /// What to index a person under, so either spelling of đ finds them.
    ///
    /// Folding alone files "Srđan Pantić" as "srdan pantic", and someone
    /// typing the far more common "srdjan" finds nobody. đ is written three
    /// ways -- đ, dj, d -- and the Search tab already answers all three by
    /// expanding the query; a substring match cannot expand a query the same
    /// way, so the *text* carries both spellings instead.
    ///
    /// Both directions: 493 members have a real đ in their name, and others
    /// typed "dj" themselves, who would otherwise be missed by "srdan".
    static func searchText(_ s: String) -> String {
        let plain = fold(s)
        var variants = [plain]
        if s.contains("đ") || s.contains("Đ") {
            variants.append(fold(s.replacingOccurrences(of: "đ", with: "dj")
                                  .replacingOccurrences(of: "Đ", with: "Dj")))
        }
        if plain.contains("dj") {
            variants.append(plain.replacingOccurrences(of: "dj", with: "d"))
        }
        return variants.joined(separator: " ")
    }

    private static func normalized(_ ch: Character) -> Character? {
        if weight[ch] != nil { return ch }
        guard ch.isLetter else { return nil }
        return SerbianLatin.alphabet.first { fold(String(ch)).first == $0 }
    }
}
