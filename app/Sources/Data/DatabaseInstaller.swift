import Foundation

enum InstallPhase: Equatable {
    case idle
    case fetchingManifest
    case downloading(received: Int64, total: Int64)
    case verifyingDownload(Double)
    case expanding(Double)
    case verifyingDatabase
    case done
    case failed(String)
}

@MainActor
@Observable
final class DatabaseInstaller: NSObject {
    var phase: InstallPhase = .idle
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?

    override init() {
        super.init()
        session = URLSession(configuration: UserAgent.configured(.default),
                             delegate: self, delegateQueue: nil)
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    /// Fetches just the manifest (a few hundred bytes) so the user can be told
    /// the real download size and consent before we pull ~330 MB over what may
    /// be a metered connection.
    func prepareManifest() async -> ArchiveManifest? {
        phase = .fetchingManifest
        do {
            let m = try await fetchManifest()
            phase = .idle
            return m
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    /// The manifest without touching `phase`, for quoting the size before the
    /// user has asked for anything. A failure is silent by design.
    func peekManifest() async -> ArchiveManifest? {
        try? await fetchManifest()
    }

    func install(manifest: ArchiveManifest) async {
        do {
            // Peak disk is the .gz plus the expanded database; the .gz is removed
            // as soon as it has been expanded, but both exist at the same moment.
            let needed = manifest.compressedSize + manifest.uncompressedSize
            let free = DatabaseLocation.freeSpaceBytes()
            guard free > needed else {
                throw InstallError.insufficientSpace(needed: needed, available: free)
            }

            let gz = try await download(manifest)

            // Hashing 333 MB and expanding it to 773 MB are seconds of solid
            // CPU work. This class is @MainActor, so running them inline froze
            // the screen on whatever it had last drawn -- the progress updates
            // below could not even be delivered, since they queue on the actor
            // the work is blocking. Off the main actor, the screen keeps
            // painting and can say what is happening.
            phase = .verifyingDownload(0)
            let digest = try await Task.detached(priority: .userInitiated) {
                try Digest.sha256(of: gz) { p in
                    Task { @MainActor in self.phase = .verifyingDownload(p) }
                }
            }.value
            guard digest.caseInsensitiveCompare(manifest.compressedSHA256) == .orderedSame else {
                try? FileManager.default.removeItem(at: gz)
                throw InstallError.checksumMismatch
            }

            phase = .expanding(0)
            let staged = DatabaseLocation.scratchDirectory.appendingPathComponent("staged.db")
            try? FileManager.default.removeItem(at: staged)
            try await Task.detached(priority: .userInitiated) {
                try GzipDecoder.decompress(from: gz, to: staged) { p in
                    Task { @MainActor in self.phase = .expanding(p) }
                }
            }.value
            try? FileManager.default.removeItem(at: gz)

            // Move into place only after expansion succeeds, so a failed install
            // never destroys a working database.
            phase = .verifyingDatabase
            DatabaseStore.close()
            let final = DatabaseLocation.databaseURL
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: staged, to: final)
            DatabaseLocation.excludeFromBackup(final)

            // `quick_check` reads all 773 MB, so this one is off the main actor
            // for the same reason as the two above.
            let verified = await Task.detached(priority: .userInitiated) {
                DatabaseStore.verify(against: manifest)
            }.value
            if case let .failure(err) = verified {
                throw err
            }
            try DatabaseLocation.writeInstalledManifest(manifest)
            try DatabaseStore.open()
            phase = .done
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Tries each candidate in order and returns the first that answers with a
    /// manifest that actually parses. A host that is missing, unreachable, or
    /// serving a 404 page instead of JSON is skipped without comment — which is
    /// what lets a not-yet-configured primary sit ahead of a working fallback.
    private func fetchManifest() async throws -> ArchiveManifest {
        var lastError: Error?
        for url in ArchiveManifest.candidateURLs {
            do {
                var req = URLRequest(url: url)
                UserAgent.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.timeoutInterval = 15          // do not stall on a dead host
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    lastError = InstallError.network("HTTP error from \(url.host ?? "server")")
                    continue
                }
                // A 200 carrying an HTML error page must also count as a miss,
                // so decoding is part of the test rather than a later step.
                return try JSONDecoder().decode(ArchiveManifest.self, from: data)
            } catch {
                lastError = error
                continue
            }
        }
        throw InstallError.network(
            "Could not reach the archive server. \(lastError?.localizedDescription ?? "")"
                .trimmingCharacters(in: .whitespaces))
    }

    private func download(_ manifest: ArchiveManifest) async throws -> URL {
        phase = .downloading(received: 0, total: manifest.compressedSize)
        var req = URLRequest(url: manifest.databaseURL)
        UserAgent.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let dest = DatabaseLocation.scratchDirectory.appendingPathComponent("archive.gz")
        try? FileManager.default.removeItem(at: dest)
        destination = dest
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.session.downloadTask(with: req).resume()
        }
    }
}

extension DatabaseInstaller: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : -1
            self.phase = .downloading(received: totalBytesWritten, total: total)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The temp file is deleted the moment this returns, so move it synchronously.
        let dest = DatabaseLocation.scratchDirectory.appendingPathComponent("archive.gz")
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: location, to: dest) }
        catch { Task { @MainActor in self.finish(.failure(error)) }; return }
        Task { @MainActor in self.finish(.success(dest)) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.finish(.failure(InstallError.network(error.localizedDescription)))
        }
    }

    @MainActor private func finish(_ result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}
