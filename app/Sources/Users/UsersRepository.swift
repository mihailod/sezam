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

    /// People who posted but never appeared in the member directory: 83 of the
    /// 3,901 authors, presumably removed before the archive was taken. They
    /// have a username and a message count, and nothing else.
    static func unlistedAuthors() throws -> [UserItem] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.id AS author_id, a.username AS username,
                       COALESCE(a.msg_count, 0) AS msgs
                FROM author a
                WHERE a.user_id IS NULL AND COALESCE(a.msg_count, 0) > 0
                """).map { row in
                let authorID: Int64 = row["author_id"]
                // Negated: this is an author id, not a user id, and the two
                // must not collide in a list that holds both kinds of row.
                return UserItem(id: -authorID, username: row["username"],
                                fullName: nil, city: nil, company: nil,
                                joinedISO: nil, lastSeenISO: nil,
                                messageCount: row["msgs"] ?? 0, authorID: authorID,
                                isListed: false)
            }
        }
    }

    /// One author with no directory entry, by name, so tapping a name in a
    /// thread still opens their messages.
    static func unlistedAuthor(username: String) throws -> UserItem? {
        guard let pool else { return nil }
        return try pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT a.id AS author_id, a.username AS username,
                       COALESCE(a.msg_count, 0) AS msgs
                FROM author a
                WHERE a.username = ? AND a.user_id IS NULL
                """, arguments: [username]).map { row in
                let authorID: Int64 = row["author_id"]
                return UserItem(id: -authorID, username: row["username"],
                                fullName: nil, city: nil, company: nil,
                                joinedISO: nil, lastSeenISO: nil,
                                messageCount: row["msgs"] ?? 0, authorID: authorID,
                                isListed: false)
            }
        }
    }

    /// One member by username, for tapping an author's name in a thread. Built
    /// from the same columns as `allUsers`, so the profile that opens is the
    /// one the directory and search would have shown.
    static func user(username: String) throws -> UserItem? {
        guard let pool else { return nil }
        return try pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT u.id AS id, u.username AS username, u.full_name AS full_name,
                       u.city AS city, u.company AS company,
                       u.member_since_iso AS joined, u.last_seen_iso AS last_seen,
                       a.id AS author_id, COALESCE(a.msg_count, 0) AS msgs
                FROM user u
                LEFT JOIN author a ON a.user_id = u.id
                WHERE u.username = ?
                """, arguments: [username]).map {
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
    /// Keyset page of one author's messages in true chronological order,
    /// oldest first or newest first.
    ///
    /// Ordered by `epoch`, never by id: ids were handed out as the mirror was
    /// parsed, so id order runs topic by topic. For mikis the id-first message
    /// is from March 1995 while his actual first is from September 1993.
    ///
    /// The id breaks ties — 88,878 author-and-minute groups hold more than one
    /// message, and a keyset walk without a total order repeats or skips rows.
    /// Served by ix_msg_author(author_id, epoch), walked backwards for newest.
    static func messages(authorID: Int64, afterEpoch: Int64, afterID: Int64,
                         limit: Int, newestFirst: Bool = false) throws -> [AuthorMessage] {
        guard let pool else { return [] }
        let head = """
            SELECT m.id AS id, m.seq AS seq, m.ts AS ts, m.epoch AS epoch,
                   m.body AS body, m.topic_id AS topic_id, t.name AS topic,
                   c.family AS family, c.volume AS volume,
                   \(ReplyCount.sqlColumn)
            FROM message m
            JOIN topic t      ON t.id = m.topic_id
            JOIN conference c ON c.id = t.conf_id
            WHERE m.author_id = ?
            """
        let sql = newestFirst
            ? head + " AND (m.epoch, m.id) < (?, ?) ORDER BY m.epoch DESC, m.id DESC LIMIT ?"
            : head + " AND (m.epoch, m.id) > (?, ?) ORDER BY m.epoch, m.id LIMIT ?"
        return try pool.read { db in
            try Row.fetchAll(db, sql: sql,
                             arguments: [authorID, afterEpoch, afterID, limit]).map {
                AuthorMessage(id: $0["id"], seq: $0["seq"] ?? 0, timestamp: $0["ts"],
                              epoch: $0["epoch"] ?? 0,
                              body: $0["body"] ?? "", topicID: $0["topic_id"] ?? 0,
                              topic: $0["topic"], family: $0["family"], volume: $0["volume"],
                              replies: $0["replies"] ?? 0)
            }
        }
    }

    /// One author's messages, most-answered first. Ties go to the older
    /// message, as in a thread's Most Replies, with the id making the order
    /// total so OFFSET pages never repeat or skip a row.
    static func mostRepliedMessages(authorID: Int64, limit: Int, offset: Int) throws -> [AuthorMessage] {
        guard let pool else { return [] }
        return try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.seq AS seq, m.ts AS ts, m.epoch AS epoch,
                       m.body AS body, m.topic_id AS topic_id, t.name AS topic,
                       c.family AS family, c.volume AS volume,
                       \(ReplyCount.sqlColumn)
                FROM message m
                JOIN topic t      ON t.id = m.topic_id
                JOIN conference c ON c.id = t.conf_id
                WHERE m.author_id = ?
                ORDER BY replies DESC, m.epoch, m.id
                LIMIT ? OFFSET ?
                """, arguments: [authorID, limit, offset]).map {
                AuthorMessage(id: $0["id"], seq: $0["seq"] ?? 0, timestamp: $0["ts"],
                              epoch: $0["epoch"] ?? 0,
                              body: $0["body"] ?? "", topicID: $0["topic_id"] ?? 0,
                              topic: $0["topic"], family: $0["family"], volume: $0["volume"],
                              replies: $0["replies"] ?? 0)
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
    /// Seconds since 1970, the key the list is ordered by.
    let epoch: Int64
    let body: String
    let topicID: Int64
    let topic: String
    let family: String
    let volume: String
    /// How many messages answered this one.
    let replies: Int

    /// Conference and topic. The message's number is not spelled here: it is
    /// its place in the whole topic, which only `MessageNumbering` knows.
    var source: String { "\(family) · \(topic)" }

    var displayDate: String { ArchiveDate.day(timestamp) ?? "" }

    var preview: String {
        body.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
