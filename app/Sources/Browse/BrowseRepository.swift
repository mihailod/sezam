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
                       -- ISO strings compare in date order, so min/max on the
                       -- text need no conversion. Kept whole rather than cut to
                       -- the month: the row shows months, the sort needs days.
                       min(t.first_ts)                AS m0,
                       max(t.last_ts)                 AS m1
                FROM conference c JOIN topic t ON t.conf_id = c.id
                WHERE t.msg_count > 0
                GROUP BY c.family
                ORDER BY c.family
                """).map {
                ConferenceFamily(family: $0["family"], messages: $0["messages"] ?? 0,
                                 topics: $0["topics"] ?? 0,
                                 firstPost: $0["m0"], lastPost: $0["m1"])
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
                       min(t.first_ts)                 AS m0,
                       max(t.last_ts)                  AS m1
                FROM conference c JOIN topic t ON t.conf_id = c.id
                WHERE c.family = ? AND t.msg_count > 0
                GROUP BY t.name
                ORDER BY messages DESC, name
                """, arguments: [family]).map {
                TopicSummary(family: family, name: $0["name"], messages: $0["messages"] ?? 0,
                             firstPost: $0["m0"], lastPost: $0["m1"])
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

    /// Who replied to each of these messages -- the reverse of `reply_seq`, for
    /// the "replied to by" hints.
    ///
    /// One query for a whole page rather than one per message. Served by
    /// ix_msg_reply(topic_id, reply_seq), which already existed: a 60-parent
    /// page on the archive's densest topic measured 0.67 ms for 83 children.
    ///
    /// Ordered by seq, so the hints read in the order the replies were written.
    static func replies(topicID: Int64, toSeqs seqs: [Int]) throws -> [Int: [ReplyRef]] {
        guard let pool, !seqs.isEmpty else { return [:] }
        let holes = Array(repeating: "?", count: seqs.count).joined(separator: ",")
        var args: [DatabaseValueConvertible] = [topicID]
        args.append(contentsOf: seqs)
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.reply_seq AS parent, m.seq AS seq, m.id AS id, a.username AS author
                FROM message m
                JOIN author a ON a.id = m.author_id
                WHERE m.topic_id = ? AND m.reply_seq IN (\(holes))
                ORDER BY m.seq
                """, arguments: StatementArguments(args))
            var out: [Int: [ReplyRef]] = [:]
            for row in rows {
                guard let parent = row["parent"] as Int? else { continue }
                out[parent, default: []].append(
                    ReplyRef(id: row["id"], seq: row["seq"] ?? 0, author: row["author"] ?? ""))
            }
            return out
        }
    }
}

/// One reply to a message: enough to label a hint and jump to it.
struct ReplyRef: Hashable, Identifiable {
    let id: Int64
    let seq: Int
    let author: String
}
