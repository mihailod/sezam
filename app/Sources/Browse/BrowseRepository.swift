import Foundation
import GRDB

/// One volume of a topic. Messages are paged within a volume by `seq`.
struct TopicVolume: Identifiable, Hashable {
    let id: Int64
    let volume: String
    let messages: Int
}

enum BrowseRepository {
    private static var pool: DatabasePool? { DatabaseStore.shared?.dbPool }

    static func families() throws -> [ConferenceFamily] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.family                       AS family,
                       sum(t.msg_count)               AS messages,
                       count(DISTINCT t.name)         AS topics,
                       -- "1995-02": ISO strings compare in date order, so
                       -- min/max on the text need no conversion.
                       min(substr(t.first_ts,1,7))    AS m0,
                       max(substr(t.last_ts,1,7))     AS m1
                FROM conference c JOIN topic t ON t.conf_id = c.id
                WHERE t.msg_count > 0
                GROUP BY c.family
                ORDER BY c.family
                """).map {
                ConferenceFamily(family: $0["family"], messages: $0["messages"] ?? 0,
                                 topics: $0["topics"] ?? 0,
                                 firstMonth: $0["m0"], lastMonth: $0["m1"])
            }
        }
    }

    /// Topics merged across every volume of the family -- the site sliced these
    /// by volume; we deliberately do not.
    static func topics(in family: String) throws -> [TopicSummary] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.name                          AS name,
                       sum(t.msg_count)                AS messages,
                       min(substr(t.first_ts,1,7))     AS m0,
                       max(substr(t.last_ts,1,7))      AS m1
                FROM conference c JOIN topic t ON t.conf_id = c.id
                WHERE c.family = ? AND t.msg_count > 0
                GROUP BY t.name
                ORDER BY messages DESC, name
                """, arguments: [family]).map {
                TopicSummary(family: family, name: $0["name"], messages: $0["messages"] ?? 0,
                             firstMonth: $0["m0"], lastMonth: $0["m1"])
            }
            // Re-sorted in Swift for the name tie-break only: SQLite's BINARY
            // collation files 23 topics (računari, štampači, trač...) after z.
            .sorted { ($1.messages, SerbianLatin.key($0.name))
                    < ($0.messages, SerbianLatin.key($1.name)) }
        }
    }

    /// Volumes in true chronological order via the numeric ordinal -- string
    /// ordering would place FORUM.10 before FORUM.2.
    static func volumes(family: String, topic: String) throws -> [TopicVolume] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.id AS id, c.volume AS volume, t.msg_count AS n
                FROM topic t JOIN conference c ON c.id = t.conf_id
                WHERE c.family = ? AND t.name = ? AND t.msg_count > 0
                ORDER BY c.ord, c.volume
                """, arguments: [family, topic]).map {
                TopicVolume(id: $0["id"], volume: $0["volume"], messages: $0["n"] ?? 0)
            }
        }
    }

    /// Messages immediately BEFORE a seq, ascending. Used when a thread is
    /// opened at an arbitrary message (from a user's history or a search hit)
    /// so the reader can walk back into the conversation.
    static func messagesBefore(topicID: Int64, beforeSeq: Int, limit: Int) throws -> [MessageRow] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM (
                  SELECT m.id AS id, m.seq AS seq, m.ts AS ts, a.username AS author,
                         m.topic_id AS topic_id, m.body AS body,
                         m.reply_seq AS rseq, m.reply_author AS rauthor, c.volume AS volume
                  FROM message m
                  JOIN author a     ON a.id = m.author_id
                  JOIN topic t      ON t.id = m.topic_id
                  JOIN conference c ON c.id = t.conf_id
                  WHERE m.topic_id = ? AND m.seq < ?
                  ORDER BY m.seq DESC
                  LIMIT ?
                ) ORDER BY seq
                """, arguments: [topicID, beforeSeq, limit]).map {
                MessageRow(id: $0["id"], topicID: $0["topic_id"] ?? 0,
                           seq: $0["seq"] ?? 0, timestamp: $0["ts"],
                           author: $0["author"], body: $0["body"] ?? "",
                           replySeq: $0["rseq"], replyAuthor: $0["rauthor"],
                           volume: $0["volume"])
            }
        }
    }

    /// Keyset page inside one volume. Ordering by `seq` is the BBS's own posting
    /// order, which is authoritative -- ~295 messages archive-wide carry corrupt
    /// timestamps, so sorting by date would misplace them.
    static func messages(topicID: Int64, afterSeq: Int, limit: Int) throws -> [MessageRow] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.seq AS seq, m.ts AS ts, a.username AS author, m.topic_id AS topic_id,
                       m.body AS body, m.reply_seq AS rseq, m.reply_author AS rauthor,
                       c.volume AS volume
                FROM message m
                JOIN author a     ON a.id = m.author_id
                JOIN topic t      ON t.id = m.topic_id
                JOIN conference c ON c.id = t.conf_id
                WHERE m.topic_id = ? AND m.seq > ?
                ORDER BY m.seq
                LIMIT ?
                """, arguments: [topicID, afterSeq, limit]).map {
                MessageRow(id: $0["id"], topicID: $0["topic_id"] ?? 0,
                           seq: $0["seq"] ?? 0, timestamp: $0["ts"],
                           author: $0["author"], body: $0["body"] ?? "",
                           replySeq: $0["rseq"], replyAuthor: $0["rauthor"],
                           volume: $0["volume"])
            }
        }
    }
}
