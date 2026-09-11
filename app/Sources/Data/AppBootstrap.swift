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

    /// Download size for the button on the download screen. Nil until a
    /// manifest has answered; the button then just says "Download".
    var knownDownloadSize: Int64?

    /// Fetches the manifest quietly when the download screen appears, so the
    /// button can quote the size before anything is tapped. It is a few
    /// hundred bytes, and it never touches the installer's phase: offline, the
    /// button simply goes without a size rather than the screen showing an error
    /// nobody asked for.
    func prefetchDownloadSize() async {
        guard knownDownloadSize == nil,
              let m = await installer.peekManifest() else { return }
        knownDownloadSize = m.compressedSize
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

    /// True when the download screen is up because the user asked for a fresh
    /// copy in Settings, rather than because the installed archive is missing
    /// or damaged. The screen uses it to drop a line that would only repeat
    /// the reason shown above it.
    private(set) var isUserRequestedRedownload = false

    /// Hands off to the download screen, which owns the single size-consent
    /// prompt. The database is only closed once a replacement is verified, so
    /// cancelling here leaves the installed archive untouched.
    func startRedownload() {
        autoStartInstall = true
        isUserRequestedRedownload = true
        state = .needsInstall(reason: "Re-downloading the archive.")
    }

    func check() {
        state = .checking
        isUserRequestedRedownload = false
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
        knownDownloadSize = m.compressedSize
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
            isUserRequestedRedownload = false
            state = .ready
        }
    }
}
