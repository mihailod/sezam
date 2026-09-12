import Foundation

/// Every date the app shows is written "03 Mar 1995".
///
/// The archive stores ISO strings -- "1996-11-15" for a join date, and
/// "1995-03-10T19:33" for a message or a last-seen -- which is the right form
/// to store and sort by, and the wrong form to read. Three views had each
/// grown their own copy of this conversion and two others were printing the
/// raw ISO, so the same date appeared in two different formats depending on
/// which screen you were on.
///
/// Deliberately not a `DateFormatter`: these are archive timestamps, already
/// in the poster's own local time, and parsing them into `Date` only to print
/// them again would drag in a time zone that would shift some of them a day.
enum ArchiveDate {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "03 Mar 1995". Nil only when there is no date at all; anything stored in
    /// a shape this cannot read is passed through as-is rather than hidden.
    static func day(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]) else {
            return String(iso.prefix(10))
        }
        // The stored day is zero-padded; the shown one is not -- "1 Jun 1995".
        return "\(d) \(months[m - 1]) \(parts[0])"
    }

    /// "19 Nov 1991 07:54", for the thread view, where the time of day is part
    /// of reading a conversation. Nil when the stored value carries no time.
    static func dayTime(_ iso: String?) -> String? {
        guard let iso, iso.count >= 16, let day = day(iso) else { return nil }
        return "\(day) \(iso.suffix(5))"
    }

    /// "Mar 1995", from either a stored timestamp or a bare "1995-03".
    static func month(_ iso: String?) -> String? {
        guard let iso, iso.count >= 7 else { return nil }
        let parts = iso.prefix(7).split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else {
            return String(iso.prefix(7))
        }
        return "\(months[m - 1]) \(parts[0])"
    }

    /// "Feb 1995 – Dec 1999" for a conference or a topic, collapsing to a
    /// single "Mar 1995" when everything in it was posted in one month.
    ///
    /// Spaced en dash, unlike the old "1995–1999": with two words on each side
    /// the tight form ran the two dates together.
    static func monthSpan(_ from: String?, _ to: String?) -> String {
        guard let lo = month(from), let hi = month(to) else { return "" }
        return lo == hi ? lo : "\(lo) – \(hi)"
    }

    /// The same shape for a real clock date -- Settings shows one, for when a
    /// re-download may be attempted again -- so the app never prints
    /// "Sep 12, 2026" on one screen and "12 Sep 2026" on another.
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        guard let d = c.day, let m = c.month, let y = c.year,
              (1...12).contains(m) else { return "" }
        return "\(d) \(months[m - 1]) \(y)"
    }
}
