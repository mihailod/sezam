import Foundation
import GRDB

/// Read-only access to the installed archive.
final class DatabaseStore {
    let dbPool: DatabasePool
    static private(set) var shared: DatabaseStore?

    init(path: String) throws {
        var config = Configuration()
        config.readonly = true
        dbPool = try DatabasePool(path: path, configuration: config)
    }

    static func open() throws {
        shared = try DatabaseStore(path: DatabaseLocation.databaseURL.path)
    }

    static func close() { shared = nil }

    /// Cheap launch-time gate. A full `quick_check` on a 764 MB file costs
    /// seconds, which is not acceptable on every cold start -- so at launch we
    /// only confirm the file is present, the right size, and actually openable.
    /// The expensive structural verification runs once, right after install.
    static func lightVerify(against manifest: ArchiveManifest) -> Result<Void, InstallError> {
        let url = DatabaseLocation.databaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        guard size == manifest.uncompressedSize else {
            return .failure(.sizeMismatch(expected: manifest.uncompressedSize, got: size))
        }
        do {
            let store = try DatabaseStore(path: url.path)
            let n = try store.dbPool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM conference") ?? -1 }
            return n > 0 ? .success(()) : .failure(.contentMismatch)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    /// Structural + content verification. A file that merely exists is not a
    /// usable archive: a half-written or truncated database opens happily and
    /// then fails deep inside a query.
    static func verify(against manifest: ArchiveManifest) -> Result<Void, InstallError> {
        let url = DatabaseLocation.databaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        guard size == manifest.uncompressedSize else {
            return .failure(.sizeMismatch(expected: manifest.uncompressedSize, got: size))
        }
        do {
            let store = try DatabaseStore(path: url.path)
            let ok = try store.dbPool.read { db -> Bool in
                let check = try String.fetchOne(db, sql: "PRAGMA quick_check") ?? "?"
                guard check == "ok" else { return false }
                let messages = try Int.fetchOne(db, sql: "SELECT count(*) FROM message") ?? -1
                let users = try Int.fetchOne(db, sql: "SELECT count(*) FROM user") ?? -1
                return messages == manifest.messageCount && users == manifest.userCount
            }
            return ok ? .success(()) : .failure(.contentMismatch)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }
}

enum InstallError: LocalizedError {
    case missing
    case sizeMismatch(expected: Int64, got: Int64)
    case contentMismatch
    case unreadable(String)
    case checksumMismatch
    case insufficientSpace(needed: Int64, available: Int64)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missing:          return "The archive has not been downloaded yet."
        case .sizeMismatch:     return "The archive is incomplete."
        case .contentMismatch:  return "The archive is incomplete or damaged."
        case .unreadable(let m):return "The archive could not be opened. \(m)"
        case .checksumMismatch: return "The download did not match its checksum."
        case let .insufficientSpace(needed, available):
            let f = ByteCountFormatter()
            return "Not enough free space. Need \(f.string(fromByteCount: needed)), "
                 + "\(f.string(fromByteCount: available)) available."
        case .network(let m):   return m
        }
    }
}
