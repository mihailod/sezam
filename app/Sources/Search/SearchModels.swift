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

    var displayDate: String { ArchiveDate.day(timestamp) ?? "" }
}

// PersonHit removed: people search now returns UserItem so that a hit
// navigates to the same destination as the Users tab.
