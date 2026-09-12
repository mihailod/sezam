import Foundation

struct ConferenceFamily: Identifiable, Hashable {
    let family: String
    let messages: Int
    let topics: Int
    /// The ends of the span as stored, "1995-02": sortable, and the form
    /// `ArchiveDate` reads. Nil for the two topics with no timestamps at all.
    let firstMonth: String?
    let lastMonth: String?
    var id: String { family }

    var span: String { ArchiveDate.monthSpan(firstMonth, lastMonth) }
}

struct TopicSummary: Identifiable, Hashable {
    let family: String
    let name: String
    let messages: Int
    let firstMonth: String?
    let lastMonth: String?
    var id: String { name }

    var span: String { ArchiveDate.monthSpan(firstMonth, lastMonth) }
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

    var replyLabel: String? {
        guard let seq = replySeq else { return nil }
        if let who = replyAuthor, !who.isEmpty { return "↩ #\(seq) \(who)" }
        return "↩ #\(seq)"
    }

    /// Bodies carry the original CRLF line endings and trailing blank lines.
    var displayBody: String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
