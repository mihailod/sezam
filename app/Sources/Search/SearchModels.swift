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

    var location: String { "\(family) · \(topic) · #\(seq)" }

    var displayDate: String {
        guard let ts = timestamp, ts.count >= 10 else { return "" }
        let d = ts.prefix(10).split(separator: "-")
        guard d.count == 3, let m = Int(d[1]) else { return String(ts.prefix(10)) }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(d[2]) \(months[max(0, min(11, m - 1))]) \(d[0])"
    }
}

// PersonHit removed: people search now returns UserItem so that a hit
// navigates to the same destination as the Users tab.
