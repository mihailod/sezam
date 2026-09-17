import UIKit

/// Builds what "Copy Message" puts on the clipboard: the message with the
/// facts from its headline, so a message pasted into a mail or a note still
/// says who wrote it, when, where it sits in the topic, and what it answers.
enum MessageClipboard {
    /// Lines above the body, in the order the headline reads them. Any of them
    /// may be absent -- a message that answers nothing has no "In reply to".
    static func text(author: String,
                     date: String,
                     source: String,
                     replyTo: String? = nil,
                     replies: [String] = [],
                     body: String) -> String {
        var lines = ["\(author) · \(date)", source]
        if let replyTo { lines.append("In reply to \(replyTo)") }
        if !replies.isEmpty { lines.append("Replies: " + replies.joined(separator: ", ")) }
        // A blank line between the headline and the message, so the two do not
        // read as one block of text once pasted.
        return lines.joined(separator: "\n") + "\n\n" + body
    }

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
