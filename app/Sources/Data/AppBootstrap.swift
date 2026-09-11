import Foundation

enum ArchiveState: Equatable {
    case checking
    case ready
    case needsInstall(reason: String?)
}

@MainActor
@Observable
final class AppBootstrap {
    var state: ArchiveState = .checking
    let installer = DatabaseInstaller()

    /// Set once the manifest is in hand, so the consent dialog can quote the
    /// real download size rather than a figure baked into the binary.
    var pendingManifest: ArchiveManifest?
    var showConsent = false
    /// Set when the user asks for a re-download from Settings, so the download
    /// screen goes straight to the size prompt instead of waiting for a tap.
    var autoStartInstall = false

    var pendingDownloadSize: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: pendingManifest?.compressedSize ?? 0)
    }

    /// Guards the About screen's manual re-download. A courtesy limit, not
    /// enforcement: deleting the app clears it. Real rate limiting would need a
    /// server we do not have.
    private let lastDownloadKey = "lastSuccessfulDownload"
    static let redownloadInterval: TimeInterval = 24 * 60 * 60

    var lastDownload: Date? {
        let t = UserDefaults.standard.double(forKey: lastDownloadKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    var redownloadAvailableAt: Date? {
        lastDownload.map { $0.addingTimeInterval(Self.redownloadInterval) }
    }

    var canRedownload: Bool {
        guard let next = redownloadAvailableAt else { return true }
        return Date() >= next
    }

    /// Hands off to the download screen, which owns the single size-consent
    /// prompt. The database is only closed once a replacement is verified, so
    /// cancelling here leaves the installed archive untouched.
    func startRedownload() {
        autoStartInstall = true
        state = .needsInstall(reason: "Re-downloading the archive.")
    }

    func check() {
        state = .checking
        guard let manifest = DatabaseLocation.installedManifest() else {
            state = .needsInstall(reason: nil); return
        }
        switch DatabaseStore.lightVerify(against: manifest) {
        case .success:
            do { try DatabaseStore.open(); state = .ready }
            catch { state = .needsInstall(reason: error.localizedDescription) }
        case .failure(let err):
            state = .needsInstall(reason: err.errorDescription)
        }
    }

    /// Step 1: fetch the manifest, then ask. No large transfer starts until the
    /// user has seen the size and agreed.
    func requestInstall() async {
        guard let m = await installer.prepareManifest() else { return }
        pendingManifest = m
        showConsent = true
    }

    func declineInstall() {
        showConsent = false
        pendingManifest = nil
    }

    /// Step 2: the user tapped OK.
    func confirmInstall() async {
        showConsent = false
        guard let m = pendingManifest else { return }
        await install(manifest: m)
    }

    func install(manifest: ArchiveManifest) async {
        await installer.install(manifest: manifest)
        if case .done = installer.phase {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastDownloadKey)
            state = .ready
        }
    }
}
