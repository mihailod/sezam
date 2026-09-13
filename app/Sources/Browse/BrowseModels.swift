import Foundation

/// Anything the browse screens list and let the reader re-order. Both sides
/// of the drill -- conferences, then the topics inside one -- carry the same
/// four facts, so `ArchiveSort` can order either.
protocol ArchiveListItem {
    /// What "alphabetical" means for this row.
    var sortName: String { get }
    var messages: Int { get }
    /// The stored timestamps of the earliest and latest message, "1995-02-03T12:19".
    /// ISO text sorts in date order, so these need no conversion. Nil only for
    /// the two topics that carry no timestamps at all.
    var firstPost: String? { get }
    var lastPost: String? { get }
}

struct ConferenceFamily: Identifiable, Hashable, ArchiveListItem {
    let family: String
    let messages: Int
    let topics: Int
    let firstPost: String?
    let lastPost: String?
    var id: String { family }

    var sortName: String { family }
    var span: String { ArchiveDate.monthSpan(firstPost, lastPost) }
}

struct TopicSummary: Identifiable, Hashable, ArchiveListItem {
    let family: String
    let name: String
    let messages: Int
    let firstPost: String?
    let lastPost: String?
    var id: String { name }

    var sortName: String { name }
    var span: String { ArchiveDate.monthSpan(firstPost, lastPost) }
}

/// How the conference list and the topic list are ordered.
///
/// There is no "date created" in the archive to offer: `topic` records only
/// the timestamps of its messages, and `conference.date_from` -- the range the
/// site printed for a volume -- equals the first post in 24 of 27 families and
/// is a few days out in the rest, once even *later* than the first message.
/// Creation and first post are one axis here, and this is it.
enum ArchiveSort: String, CaseIterable, Identifiable {
    case firstPost, messages, lastActive, alphabetical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .firstPost:    return "First Post"
        case .messages:     return "# of Messages"
        case .lastActive:   return "Last Active"
        case .alphabetical: return "Alphabetical"
        }
    }

    /// Ordered as asked, with the name breaking every tie so the list never
    /// shuffles between two runs that compare equal.
    func apply<T: ArchiveListItem>(_ items: [T]) -> [T] {
        // Folded once per row, not once per comparison: ICU folding inside a
        // comparator is the mistake that cost 194 ms on the Users list.
        let keyed = items.map { (key: SerbianLatin.key($0.sortName), item: $0) }
        switch self {
        case .alphabetical:
            return keyed.sorted { $0.key < $1.key }.map(\.item)
        case .messages:
            return keyed.sorted { ($1.item.messages, $0.key) < ($0.item.messages, $1.key) }
                .map(\.item)
        case .firstPost:
            // Oldest first. A row with no timestamp sorts last rather than
            // first, which is where an empty string would put it.
            return keyed.sorted {
                ($0.item.firstPost ?? "9", $0.key) < ($1.item.firstPost ?? "9", $1.key)
            }.map(\.item)
        case .lastActive:
            // Most recently active first, so a dead conference sinks.
            return keyed.sorted {
                ($1.item.lastPost ?? "", $0.key) < ($0.item.lastPost ?? "", $1.key)
            }.map(\.item)
        }
    }
}

struct MessageRow: Identifiable, Hashable {
    let id: Int64
    let topicID: Int64
    let seq: Int
    let timestamp: String?
    let author: String
    let body: String
    let replySeq: Int?
    let replyAuthor: String?
    let volume: String

    /// "19 Nov 1991 07:54": in a thread the time of day is worth showing.
    var displayDate: String { ArchiveDate.dayTime(timestamp) ?? "" }

    /// U+FE0E forces text presentation: bare "↩" is drawn by iOS as the blue
    /// emoji arrow-in-a-box, which sat oddly beside the hairline "↳" of the
    /// replies below it. The pair has to look like one family of marks.
    var replyLabel: String? {
        guard let seq = replySeq else { return nil }
        if let who = replyAuthor, !who.isEmpty { return "↩\u{FE0E} #\(seq) \(who)" }
        return "↩\u{FE0E} #\(seq)"
    }

    /// Bodies carry the original CRLF line endings and trailing blank lines.
    var displayBody: String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
