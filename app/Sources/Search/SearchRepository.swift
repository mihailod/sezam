import Foundation
import GRDB

struct ArchiveCounts { let messages: Int; let users: Int }

enum SearchRepository {
    private static var pool: DatabasePool? { DatabaseStore.shared?.dbPool }

    /// Read from the installed database rather than baked into the binary --
    /// the help text must not quote a figure the shipped archive disagrees with.
    static func counts() -> ArchiveCounts {
        guard let pool,
              let r = try? pool.read({ db -> (Int, Int) in
                  (try Int.fetchOne(db, sql: "SELECT count(*) FROM message") ?? 0,
                   try Int.fetchOne(db, sql: "SELECT count(*) FROM user") ?? 0)
              })
        else { return ArchiveCounts(messages: 0, users: 0) }
        return ArchiveCounts(messages: r.0, users: r.1)
    }

    /// Total hits, for the section headers. Counting skips the ranking the
    /// paged query has to do, so it is cheap: ~50 ms at worst for a very
    /// common prefix ("pro*", 254,701 messages), usually under 5 ms. Every
    /// message joins to an author, topic and conference, so this is exactly
    /// the number the paged list would reach.
    static func hitCounts(matching expression: String) -> (people: Int, messages: Int) {
        guard let pool else { return (0, 0) }
        // Counted separately. A column-scoped query like author:mihailod is
        // valid for messages but an error for people -- user_search has no
        // author column -- and in a single read that error zeroed the message
        // count too, showing "Messages (0 hits)" above 176 results.
        func count(_ table: String) -> Int {
            (try? pool.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table) WHERE \(table) MATCH ?",
                                 arguments: [expression]) ?? 0
            }) ?? 0
        }
        return (people: count("user_search"), messages: count("search"))
    }

    static func messages(matching expression: String, limit: Int, offset: Int) throws -> [MessageHit] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.topic_id AS topic_id, m.seq AS seq,
                       a.username AS author, c.family AS family,
                       t.name AS topic, c.volume AS volume, m.ts AS ts, m.body AS body
                FROM search s
                JOIN message m    ON m.id = s.rowid
                JOIN author a     ON a.id = m.author_id
                JOIN topic t      ON t.id = m.topic_id
                JOIN conference c ON c.id = t.conf_id
                WHERE search MATCH ?
                ORDER BY rank
                LIMIT ? OFFSET ?
                """, arguments: [expression, limit, offset]).map {
                MessageHit(id: $0["id"], topicID: $0["topic_id"] ?? 0,
                           seq: $0["seq"] ?? 0,
                           author: $0["author"], family: $0["family"],
                           topic: $0["topic"], volume: $0["volume"],
                           timestamp: $0["ts"], body: $0["body"] ?? "")
            }
        }
    }

    /// Returns UserItem -- the same type the Users tab lists -- so a search hit
    /// navigates to exactly the same screen rather than a parallel one.
    ///
    /// Joins on a.user_id, not lower(a.username)=lower(u.username): wrapping
    /// both sides in lower() makes the index unusable and turns this into a
    /// nested scan.
    static func people(matching expression: String, limit: Int) throws -> [UserItem] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT u.id AS id, u.username AS username, u.full_name AS full_name,
                       u.city AS city, u.company AS company,
                       u.member_since_iso AS joined, u.last_seen_iso AS last_seen,
                       a.id AS author_id, COALESCE(a.msg_count, 0) AS msgs
                FROM user_search s
                JOIN user u  ON u.id = s.rowid
                LEFT JOIN author a ON a.user_id = u.id
                WHERE user_search MATCH ?
                ORDER BY msgs DESC
                LIMIT ?
                """, arguments: [expression, limit]).map {
                UserItem(id: $0["id"], username: $0["username"], fullName: $0["full_name"],
                         city: $0["city"], company: $0["company"],
                         joinedISO: $0["joined"], lastSeenISO: $0["last_seen"],
                         messageCount: $0["msgs"] ?? 0, authorID: $0["author_id"])
            }
        }
    }
}
