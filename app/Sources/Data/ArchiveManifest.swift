import Foundation

/// Small JSON published next to the database on archive.org. Fetching it first
/// (a few hundred bytes) tells the app what a complete, uncorrupted install
/// looks like -- and lets the database be replaced without an app release.
struct ArchiveManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var databaseURL: URL          // the .gz
    var compressedSize: Int64
    var compressedSHA256: String
    var uncompressedSize: Int64
    var messageCount: Int
    var userCount: Int
    var builtAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case databaseURL = "database_url"
        case compressedSize = "compressed_size"
        case compressedSHA256 = "compressed_sha256"
        case uncompressedSize = "uncompressed_size"
        case messageCount = "message_count"
        case userCount = "user_count"
        case builtAt = "built_at"
    }

    /// Where the app looks for the manifest, in order. The first that answers
    /// with valid JSON wins; the rest are never contacted.
    ///
    /// Only these URLs are baked into the binary. Where the *database* lives is
    /// read from whichever manifest answers, so the payload can move hosts with
    /// no app update. Listing more than one means the manifest can move too, as
    /// long as one of the listed locations still resolves — the primary can be
    /// a host that does not exist yet, and the app quietly uses the fallback
    /// until it does.
    static var candidateURLs: [URL] {
        if let list = Bundle.main.object(forInfoDictionaryKey: "SezamManifestURLs") as? [String] {
            let urls = list.compactMap(URL.init(string:))
            if !urls.isEmpty { return urls }
        }
        return [URL(string: "http://localhost:8000/sezam-manifest.json")!]
    }
}
