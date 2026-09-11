import Foundation
import GRDB

enum UsersRepository {
    private static var pool: DatabasePool? { DatabaseStore.shared?.dbPool }

    /// The whole directory is a few thousand rows, so it is loaded once and
    /// sorted/grouped in memory -- far simpler than seven indexed sort orders.
    static func allUsers() throws -> [UserItem] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT u.id AS id, u.username AS username, u.full_name AS full_name,
                       u.city AS city, u.company AS company,
                       u.member_since_iso AS joined, u.last_seen_iso AS last_seen,
                       a.id AS author_id, COALESCE(a.msg_count, 0) AS msgs
                FROM user u
                -- a.user_id, not lower(a.username)=lower(u.username): wrapping
                -- both sides in lower() makes the index unusable and turns this
                -- into 8,105 x 3,901 nested scans (4,027 ms vs 8 ms).
                LEFT JOIN author a ON a.user_id = u.id
                """).map {
                UserItem(id: $0["id"], username: $0["username"], fullName: $0["full_name"],
                         city: $0["city"], company: $0["company"],
                         joinedISO: $0["joined"], lastSeenISO: $0["last_seen"],
                         messageCount: $0["msgs"] ?? 0, authorID: $0["author_id"])
            }
        }
    }

    /// Keyset page of one author's messages, ordered by message id as asked.
    /// Served by ix_msg_author_id -- without that index this scans the whole
    /// table by rowid (629 ms); with it, 0.11 ms.
    static func messages(authorID: Int64, afterID: Int64, limit: Int) throws -> [AuthorMessage] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.seq AS seq, m.ts AS ts, m.body AS body,
                       m.topic_id AS topic_id, t.name AS topic,
                       c.family AS family, c.volume AS volume
                FROM message m
                JOIN topic t      ON t.id = m.topic_id
                JOIN conference c ON c.id = t.conf_id
                WHERE m.author_id = ? AND m.id > ?
                ORDER BY m.id
                LIMIT ?
                """, arguments: [authorID, afterID, limit]).map {
                AuthorMessage(id: $0["id"], seq: $0["seq"] ?? 0, timestamp: $0["ts"],
                              body: $0["body"] ?? "", topicID: $0["topic_id"] ?? 0,
                              topic: $0["topic"], family: $0["family"], volume: $0["volume"])
            }
        }
    }

    /// The topic summary a message belongs to, so tapping it can open the thread.
    static func topicSummary(family: String, name: String) throws -> TopicSummary? {
        try BrowseRepository.topics(in: family).first { $0.name == name }
    }
}

struct AuthorMessage: Identifiable, Hashable {
    let id: Int64
    let seq: Int
    let timestamp: String?
    let body: String
    let topicID: Int64
    let topic: String
    let family: String
    let volume: String

    var location: String { "\(family) · \(topic) · #\(seq)" }

    var displayDate: String {
        guard let ts = timestamp, ts.count >= 10 else { return "" }
        let d = ts.prefix(10).split(separator: "-")
        guard d.count == 3, let m = Int(d[1]) else { return String(ts.prefix(10)) }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(d[2]) \(months[max(0, min(11, m - 1))]) \(d[0])"
    }

    var preview: String {
        body.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
