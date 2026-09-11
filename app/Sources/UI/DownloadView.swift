import SwiftUI

struct DownloadView: View {
    @Bindable var bootstrap: AppBootstrap
    var reason: String?

    private let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text("Sezam Archive").font(.title2.weight(.semibold))
            Text(headline)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            if bootstrap.installer.isBusy {
                VStack(spacing: 8) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                    Text(detail).font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            } else {
                Button {
                    Task { await bootstrap.requestInstall() }
                } label: {
                    Text(isRetry ? "Try Again" : "Download")
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
            }
        }
        .alert("Download Archive", isPresented: $bootstrap.showConsent) {
            Button("OK") { Task { await bootstrap.confirmInstall() } }
            Button("Later", role: .cancel) { bootstrap.declineInstall() }
        } message: {
            Text("One-time Sezam archive (\(bootstrap.pendingDownloadSize)) "
                 + "download is needed.")
        }
    }

    private var isRetry: Bool {
        if case .failed = bootstrap.installer.phase { return true }
        return reason != nil
    }

    private var headline: String {
        if case let .failed(msg) = bootstrap.installer.phase { return msg }
        if let reason { return "\(reason)\nThe archive will be downloaded again." }
        return "The message archive is downloaded once, then works offline."
    }

    private var fraction: Double {
        switch bootstrap.installer.phase {
        case let .downloading(received, total): return total > 0 ? Double(received) / Double(total) : 0
        case let .verifyingDownload(p):         return p
        case let .expanding(p):                 return p
        case .verifyingDatabase, .done:         return 1
        default:                                return 0
        }
    }

    private var detail: String {
        switch bootstrap.installer.phase {
        case .fetchingManifest: return "Contacting archive…"
        case let .downloading(received, total):
            return total > 0
                ? "\(bytes.string(fromByteCount: received)) of \(bytes.string(fromByteCount: total))"
                : bytes.string(fromByteCount: received)
        case let .verifyingDownload(p): return String(format: "Verifying download… %.0f%%", p * 100)
        case let .expanding(p):         return String(format: "Expanding… %.0f%%", p * 100)
        case .verifyingDatabase:        return "Checking archive…"
        case .done:                     return "Ready"
        default:                        return ""
        }
    }
}
