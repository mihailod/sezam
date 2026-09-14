import SwiftUI

struct DownloadView: View {
    @Bindable var bootstrap: AppBootstrap
    var reason: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56)).foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("Sezam Archive")
                    .font(.largeTitle.bold())
                if let activity {
                    Text(activity)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            // Nothing between the title and the bar while an install is simply
            // running: the two lines above already say what is happening. Only
            // a failure, or a reason the archive is being replaced, earns a
            // paragraph here.
            if let message {
                Text(message)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            if bootstrap.installer.isBusy {
                VStack(spacing: 8) {
                    DownloadBar(value: fraction)
                    Text(detail).font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                Button {
                    Task { await start() }
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        // The one screen in the app that is a centred column rather than a
        // list, so it is the one screen that has to be told how wide to be:
        // stretched across an iPad it would be a lone button a metre wide.
        // No effect on iPhone, which is never wider than this.
        .frame(maxWidth: Device.isPad ? Device.readableColumnWidth : .infinity)
        .frame(maxWidth: .infinity)
        .task {
            if bootstrap.canInstallFromBundle {
                // Nothing to ask and nothing to fetch: begin the moment the
                // screen appears, so the first launch is a progress bar rather
                // than a button the user has no reason not to tap.
                await bootstrap.installBundled()
            } else {
                await bootstrap.prefetchDownloadSize()
            }
        }
        .alert("Download Sezam Archive", isPresented: $bootstrap.showConsent) {
            Button("OK") { Task { await bootstrap.confirmInstall() } }
            Button("Later", role: .cancel) { bootstrap.declineInstall() }
        } message: {
            Text("Start one-time Sezam Archive "
                 + "(\(Megabytes.text(bootstrap.pendingManifest?.compressedSize ?? 0))) download?")
        }
    }

    /// Whether this screen is unpacking the copy that shipped with the app
    /// rather than fetching one. Everything the screen says branches on it.
    private var isBundled: Bool { bootstrap.isBundledInstall || bootstrap.canInstallFromBundle }

    /// A box being opened, against an arrow coming down from a server.
    private var icon: String { isBundled ? "shippingbox" : "arrow.down.circle" }

    /// The second title line: what is being done to the archive right now, or
    /// nil before anything has started, when the button says it instead.
    private var activity: String? {
        guard isDownloading else { return nil }
        return isBundled ? "Decompressing" : "Downloading"
    }

    /// Starts whichever install this screen is for. The bundled one needs no
    /// consent -- there is nothing to consent to -- so it goes straight to work.
    private func start() async {
        if bootstrap.canInstallFromBundle {
            await bootstrap.installBundled()
        } else {
            await bootstrap.requestInstall()
        }
    }

    /// An attempt that failed is worth offering again by name. Otherwise the
    /// button says what it will do, with the size once a manifest has answered:
    private var buttonTitle: String {
        if case .failed = bootstrap.installer.phase { return "Try Again" }
        // No size on the bundled button: the megabytes were the warning about
        // a transfer, and there is no transfer.
        if isBundled { return "Decompress the Archive" }
        let size = bootstrap.knownDownloadSize.map { " (\(Megabytes.text($0)))" } ?? ""
        // An archive that will not pass its checks: a copy is already
        // installed, so this replaces it.
        if reason != nil { return "Re-download" + size }
        return "Download" + size
    }

    /// Past the consent prompt: the transfer itself or the steps after it.
    private var isDownloading: Bool {
        switch bootstrap.installer.phase {
        case .downloading, .verifyingDownload, .expanding, .verifyingDatabase, .done: return true
        default: return false
        }
    }

    /// The work the bar was tracking is finished and something slower-witted
    /// is happening -- a bar parked at 100% with nothing said looks stuck.
    ///
    /// For a download that includes the expansion, which comes after every
    /// byte is in. For the bundled install the expansion *is* the work, so
    /// there it is the one phase this must not claim.
    private var isInitializing: Bool {
        switch bootstrap.installer.phase {
        case let .downloading(received, total): return total > 0 && received >= total
        case .expanding: return !isBundled
        case .verifyingDownload, .verifyingDatabase, .done: return true
        default: return false
        }
    }

    // The span is written out rather than read from the archive: this screen
    // exists because there is no archive yet to read it from.
    private var message: String? {
        if case let .failed(msg) = bootstrap.installer.phase { return msg }
        // Whatever is happening is named in the title and measured by the bar.
        if isDownloading { return nil }
        // A damaged or missing archive states the problem, so it is worth
        // saying what happens next.
        if let reason {
            return isBundled ? "\(reason)\nDecompressing it again."
                             : "\(reason)\nDownloading it again."
        }
        // The bundled archive needs no explanation before it starts -- it
        // starts by itself, and the user is looking at this for a moment. A
        // download is a transfer they should be told about first.
        if isBundled { return nil }
        return "The complete 1989–1999 Sezam Archive needs to be downloaded once "
            + "for offline use by the app."
    }

    private var fraction: Double {
        // The bundled install's own progress, before the shared checks below
        // would round it up to a finished download.
        if case let .expanding(p) = bootstrap.installer.phase, isBundled { return p }
        if isInitializing { return 1 }
        if case let .downloading(received, total) = bootstrap.installer.phase, total > 0 {
            return Double(received) / Double(total)
        }
        return 0
    }

    private var detail: String {
        if case let .expanding(p) = bootstrap.installer.phase, isBundled {
            // A percentage only: there are no megabytes crossing anything, and
            // quoting the compressed size here would read as a transfer.
            return "\(Int(p * 100))% decompressed"
        }
        if isInitializing {
            return isBundled ? "Decompression done! Initializing…" : "Download done! Initializing…"
        }
        switch bootstrap.installer.phase {
        case .fetchingManifest: return "Contacting archive…"
        case let .downloading(received, total):
            // Both rounded down, so it never claims 100% or the full size
            // before the last byte -- and at that point isInitializing takes over.
            let got = Megabytes.text(received, rounded: .down)
            guard total > 0 else { return got }
            let percent = Int(Double(received) * 100 / Double(total))
            return "\(percent)% (\(got) of \(Megabytes.text(total)))"
        default: return ""
        }
    }
}

/// Whole megabytes, counted in thousands the way Files and Settings count
/// them. "333.3 MB" is precision nobody needs for a one-off download, and
/// during the transfer the decimal only flickers.
///
/// The space before "MB" is non-breaking: the consent alert wrapped between
/// "(333" and "MB)", splitting the number from its unit.
enum Megabytes {
    static func text(_ bytes: Int64,
                     rounded rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> String {
        "\(Int((Double(bytes) / 1_000_000).rounded(rule)))\u{00A0}MB"
    }
}

/// The system linear progress bar is a hairline, barely visible on a phone;
/// `scaleEffect` would thicken it but squash its rounded ends. At this weight
/// it reads as the subject of the screen rather than a detail on it.
private struct DownloadBar: View {
    let value: Double

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: g.size.width * clamped)
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Download progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}
