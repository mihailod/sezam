import Foundation

enum AppInfo {
    static let displayName = "Sezam YU"
    static let author = "Mihailo Despotovic"

    static var appCopyright: String { "iPhone App: © 2026 \(author)" }
    static let databaseCredit = "Archive: public domain (oldsezam.net)"

    /// The heading the archive notice is published under.
    static let archiveNoticeHeading = "oldsezam.net/Privacy (as of 9/9/2026):"

    /// The archive notice, reproduced from the original site.
    static let archiveNotice = """
        This message archive is read-only and in public domain, decades after \
        the site ceased operation in Belgrade, Serbia.
        """

    /// Epigraphs shown on the cards that close the Settings panel.
    struct Epigraph: Identifiable {
        let quote: String
        let author: String
        var id: String { quote }
    }

    static let epigraphs = [
        Epigraph(quote: "The purpose of computing is insight, not numbers.",
                 author: "Richard Hamming"),
        Epigraph(quote: "Data isn\u{2019}t information, any more than fifty tons "
                 + "of cement is a skyscraper.",
                 author: "Clifford Stoll"),
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionLine: String { "Version \(version) (\(build))" }
}
