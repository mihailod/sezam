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

    /// True while the archive being installed is the one that shipped inside
    /// the app, so the screen can talk about decompressing rather than
    /// downloading. Stays set on failure, so the error is shown in the same
    /// language as the attempt that produced it.
    private(set) var isBundledInstall = false

    /// Whether this install can be served from the app bundle rather than the
    /// network: the first launch, and equally a damaged archive, where making
    /// the user fetch 333 MB they already have would be perverse.
    var canInstallFromBundle: Bool { BundledArchive.isAvailable }

    /// The first launch: expand what shipped with the app. No consent prompt,
    /// because nothing is transferred and nothing leaves the device.
    func installBundled() async {
        guard let manifest = BundledArchive.manifest, let gz = BundledArchive.gzURL else { return }
        isBundledInstall = true
        await installer.installFromBundle(manifest, gz: gz)
        if case .done = installer.phase {
            isBundledInstall = false
            state = .ready
        }
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
            state = .ready
        }
    }
}
