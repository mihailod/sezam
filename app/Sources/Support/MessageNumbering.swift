import Foundation

/// Numbers a message by its place in the whole topic, not by the number the
/// board gave it.
///
/// The archive split long topics into volumes -- 263 of 463 topics have more
/// than one -- and `seq` restarts in each, so FORUM · srbija contains sixteen
/// messages called #1. The app hides volumes as containers, so showing those
/// numbers meant a thread counting up to #1,869 and then starting again at #1.
/// Here a message is "#1,402 (of 25,425)": its position among everything ever
/// posted to that topic.
///
/// Built from 1,405 rows once (2.9 ms), with each volume's seq list read the
/// first time a message from it is numbered (under 1 ms). Deletions left gaps
/// in seq, so a place inside a volume is counted from that list rather than
/// taken from the seq itself.
@MainActor
final class MessageNumbering {
    static let shared = MessageNumbering()
    private init() {}

    /// Messages in all the volumes that come before this one in its topic.
    private var before: [Int64: Int] = [:]
    /// Messages in the whole topic this volume belongs to.
    private var topicTotal: [Int64: Int] = [:]
    private var seqs: [Int64: [Int]] = [:]
    private var loaded = false

    /// Position of a message in its topic, and the size of that topic.
    func position(topicID: Int64, seq: Int) -> (number: Int, total: Int)? {
        load()
        guard let start = before[topicID], let total = topicTotal[topicID] else { return nil }
        let list = volumeSeqs(topicID)
        // How many messages in this volume come at or before this one.
        var low = 0, high = list.count
        while low < high {
            let mid = (low + high) / 2
            if list[mid] <= seq { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        return (start + low, total)
    }

    /// "#1,402" -- for a reply hint, where the total would be noise.
    func number(topicID: Int64, seq: Int) -> String {
        guard let place = position(topicID: topicID, seq: seq) else { return "#\(seq)" }
        return "#\(place.number.formatted())"
    }

    /// "#1,402 (of 25,425)" -- a number alone says little about where in a
    /// decade of a topic the reader has landed.
    func label(topicID: Int64, seq: Int) -> String {
        guard let place = position(topicID: topicID, seq: seq) else { return "#\(seq)" }
        return "#\(place.number.formatted()) (of \(place.total.formatted()))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        var running: [String: Int] = [:]
        var totals: [String: Int] = [:]
        let rows = (try? BrowseRepository.volumeCounts()) ?? []
        for row in rows { totals[row.topic, default: 0] += row.count }
        for row in rows {
            before[row.topicID] = running[row.topic, default: 0]
            topicTotal[row.topicID] = totals[row.topic] ?? row.count
            running[row.topic, default: 0] += row.count
        }
    }

    private func volumeSeqs(_ topicID: Int64) -> [Int] {
        if let cached = seqs[topicID] { return cached }
        let list = (try? BrowseRepository.seqs(topicID: topicID)) ?? []
        seqs[topicID] = list
        return list
    }
}
