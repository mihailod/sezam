import Foundation

struct MessageHit: Identifiable, Hashable {
    let id: Int64
    let topicID: Int64      // needed to open the thread at this message
    let seq: Int
    let author: String
    let family: String
    let topic: String
    let volume: String
    let timestamp: String?
    let body: String
    /// How many messages answered this one.
    let replies: Int

    var location: String { "\(family) · \(topic) · #\(seq)" }

    /// "(5 replies)", "(1 reply)", "(no replies)". Shown on every hit, not just
    /// under Most Replies, so the count is visible before anyone goes looking
    /// for a way to sort by it.
    var repliesLabel: String { ReplyCount.label(replies) }

    var displayDate: String { ArchiveDate.day(timestamp) ?? "" }
}

/// How the Messages half of a search is ordered. People are not affected: that
/// section is a shortlist of the eight most prolific matches, and re-sorting
/// eight names by date would answer no question anyone asks.
///
/// Measured on the full archive, warm, median of five. The heaviest prefix,
/// "beog*" at 435k hits, takes 261 ms by relevance, ~100 ms by date and 339 ms
/// by replies -- the default, so the slowest order is the one every search
/// pays. On an ordinary word ("windows", 22k hits) that is 23 ms.
enum MessageSearchSort: String, CaseIterable, Identifiable, Hashable {
    // Declaration order is menu order: the default leads.
    case mostReplies, relevance, oldest, newest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance:   return "Relevance"
        case .mostReplies: return "Most Replies"
        case .oldest:      return "Oldest"
        case .newest:      return "Newest"
        }
    }
}

// PersonHit removed: people search now returns UserItem so that a hit
// navigates to the same destination as the Users tab.
