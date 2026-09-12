import Foundation

/// The compressed archive that ships inside the app.
///
/// With it present the first launch needs no network at all: no manifest to
/// fetch, no consent to ask for a 333 MB transfer over what might be a metered
/// connection, just a decompression of a file that is already on the device.
///
/// The download path is not retired. It still serves the re-download in
/// Settings, and it still serves a build that ships without the .gz -- the
/// file is deliberately not in the repository (it is far past GitHub's 100 MB
/// limit), so a fresh clone builds an app that downloads, and everything below
/// answers nil rather than trapping.
enum BundledArchive {
    /// The .gz inside the app bundle. Named with its full "sezam.db.gz" and no
    /// extension argument: the name already contains a dot, and splitting it
    /// as name + extension finds nothing.
    static var gzURL: URL? {
        Bundle.main.url(forResource: "sezam.db.gz", withExtension: nil)
    }

    /// The manifest describing that .gz -- byte-for-byte the one published
    /// beside the archive, so an install from the bundle records exactly what
    /// an install from the network would have.
    static var manifest: ArchiveManifest? {
        guard let url = Bundle.main.url(forResource: "sezam-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ArchiveManifest.self, from: data)
    }

    /// Both halves have to be there: the .gz alone gives nothing to check the
    /// expanded database against, and the manifest alone has nothing to expand.
    static var isAvailable: Bool { gzURL != nil && manifest != nil }
}
