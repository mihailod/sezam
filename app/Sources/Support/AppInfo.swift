import Foundation

enum AppInfo {
    static let displayName = "Sezam YU"
    static let author = "Mihailo Despotovic"

    /// Named for the device it is running on: the same binary is the
    /// iPhone app and the iPad app, and calling itself the iPhone app on
    /// an iPad is the tell of a phone build someone has sideloaded.
    static var appCopyright: String {
        "\(Device.isPad ? "iPad" : "iPhone") App: © 2026 \(author)"
    }
    static let databaseCredit = "Archive: public domain (oldsezam.net)"

    /// The heading the archive notice is published under.
    static let archiveNoticeHeading = "oldsezam.net/Privacy (as of 9 Sep 2026):"

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

    /// The card that closes the panel. Three paragraphs, kept exactly as
    /// written -- the lower case and the handles are the register of the board
    /// these people posted on, not a style slip to be tidied up.
    static let credits = [
        "created by mihailod",
        "shouts go to d.m. / davor, kcurcic, mrbin, shoom, nradeta, wisil, "
            + "jujo, baltazar, spantic, ikordic, cupko",
        "dedicated to dejanr",
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionLine: String { "Version \(version) (\(build))" }
}
