import Foundation

enum DatabaseLocation {
    /// Application Support, not Documents: the database is a redownloadable
    /// cache-like artifact, not user content, and must never appear in Files.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL { directory.appendingPathComponent("sezam.db") }
    static var installedManifestURL: URL { directory.appendingPathComponent("installed-manifest.json") }
    static var scratchDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sezam-install", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A 764 MB file in an iCloud backup would be hostile to the user.
    static func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    static func freeSpaceBytes() -> Int64 {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func installedManifest() -> ArchiveManifest? {
        guard let data = try? Data(contentsOf: installedManifestURL) else { return nil }
        return try? JSONDecoder().decode(ArchiveManifest.self, from: data)
    }

    static func writeInstalledManifest(_ m: ArchiveManifest) throws {
        try JSONEncoder().encode(m).write(to: installedManifestURL, options: .atomic)
    }
}
