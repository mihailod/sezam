import SwiftUI

struct DownloadView: View {
    @Bindable var bootstrap: AppBootstrap
    var reason: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text(isDownloading ? "Sezam Archive Downloading" : "Sezam Archive")
                .font(.title2.weight(.semibold))
            Text(headline)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            if bootstrap.installer.isBusy {
                VStack(spacing: 8) {
                    DownloadBar(value: fraction)
                    Text(detail).font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                Button {
                    Task { await bootstrap.requestInstall() }
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
        .task {
            if bootstrap.autoStartInstall {
                bootstrap.autoStartInstall = false
                await bootstrap.requestInstall()
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

    /// An attempt that failed is worth offering again by name. Otherwise the
    /// button says what it will do, with the size once a manifest has answered:
    /// a re-download the user asked for is not a retry, nothing went wrong.
    private var buttonTitle: String {
        if case .failed = bootstrap.installer.phase { return "Try Again" }
        let size = bootstrap.knownDownloadSize.map { " (\(Megabytes.text($0)))" } ?? ""
        // Asked for in Settings, or forced by an archive that will not pass its
        // checks: either way a copy is already installed, so this replaces it.
        if bootstrap.isUserRequestedRedownload || reason != nil { return "Re-download" + size }
        return "Download" + size
    }

    /// Past the consent prompt: the transfer itself or the steps after it.
    private var isDownloading: Bool {
        switch bootstrap.installer.phase {
        case .downloading, .verifyingDownload, .expanding, .verifyingDatabase, .done: return true
        default: return false
        }
    }

    /// Every byte is in. Checking, expanding and opening the archive still take
    /// a while, and a bar parked at 100% with nothing said looks stuck.
    private var isInitializing: Bool {
        switch bootstrap.installer.phase {
        case let .downloading(received, total): return total > 0 && received >= total
        case .verifyingDownload, .expanding, .verifyingDatabase, .done: return true
        default: return false
        }
    }

    // The span is written out rather than read from the archive: this screen
    // exists because there is no archive yet to read it from.
    private var headline: String {
        if case let .failed(msg) = bootstrap.installer.phase { return msg }
        if isDownloading {
            return "The complete 1989–1999 Sezam Archive is now downloading "
                + "for offline use by the app."
        }
        // A re-download the user asked for already says so in the reason; a
        // second sentence would only repeat it. A damaged or missing archive
        // states the problem, so there it is worth saying what happens next.
        if let reason {
            return bootstrap.isUserRequestedRedownload ? reason : "\(reason)\nDownloading it again."
        }
        return "The complete 1989–1999 Sezam Archive needs to be downloaded once "
            + "for offline use by the app."
    }

    private var fraction: Double {
        if isInitializing { return 1 }
        if case let .downloading(received, total) = bootstrap.installer.phase, total > 0 {
            return Double(received) / Double(total)
        }
        return 0
    }

    private var detail: String {
        if isInitializing { return "Download done! Initializing…" }
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
/// `scaleEffect` would thicken it but squash its rounded ends.
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
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Download progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}
