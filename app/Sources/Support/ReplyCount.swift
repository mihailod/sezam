import Foundation

/// "(5 replies)", "(1 reply)", "(no replies)" -- one wording wherever a list of
/// messages shows how many times each was answered, so search results and a
/// member's message list cannot drift apart.
enum ReplyCount {
    static func label(_ n: Int) -> String {
        switch n {
        case 0:  return "(no replies)"
        case 1:  return "(1 reply)"
        default: return "(\(n) replies)"
        }
    }

    /// The per-message count, as a result column. It runs only for the rows a
    /// query's LIMIT keeps, through ix_msg_reply(topic_id, reply_seq).
    static let sqlColumn = """
        (SELECT count(*) FROM message r
         WHERE r.topic_id = m.topic_id AND r.reply_seq = m.seq) AS replies
        """
}
