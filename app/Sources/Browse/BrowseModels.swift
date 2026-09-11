import Foundation

struct ConferenceFamily: Identifiable, Hashable {
    let family: String
    let messages: Int
    let topics: Int
    let firstYear: Int?
    let lastYear: Int?
    var id: String { family }

    var yearSpan: String {
        guard let f = firstYear, let l = lastYear else { return "" }
        return f == l ? "\(f)" : "\(f)–\(l)"
    }
}

struct TopicSummary: Identifiable, Hashable {
    let family: String
    let name: String
    let messages: Int
    let firstYear: Int?
    let lastYear: Int?
    var id: String { name }

    var yearSpan: String {
        guard let f = firstYear, let l = lastYear else { return "" }
        return f == l ? "\(f)" : "\(f)–\(l)"
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

    /// "19 Nov 1991 07:54" from the stored ISO form.
    var displayDate: String {
        guard let ts = timestamp, ts.count >= 16 else { return "" }
        let d = ts.prefix(10).split(separator: "-")
        let time = ts.suffix(5)
        guard d.count == 3, let m = Int(d[1]) else { return String(ts.prefix(10)) }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let mon = (1...12).contains(m) ? months[m - 1] : d[1].description
        return "\(d[2]) \(mon) \(d[0]) \(time)"
    }

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
