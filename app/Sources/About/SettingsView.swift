import SwiftUI

struct SettingsView: View {
    @Environment(AppBootstrap.self) private var bootstrap
    @State private var settings = AppSettings.shared
    @State private var confirmRedownload = false
    /// The size actually in effect: the system's when nothing is overridden,
    /// so the slider starts where the user already is rather than snapping.
    @Environment(\.dynamicTypeSize) private var effectiveSize
    @Environment(\.systemTypeSize) private var systemSize

    private var sizeSlider: Binding<Double> {
        Binding(
            get: { Double(settings.overrideIndex ?? AppSettings.index(of: systemSize)) },
            set: { value in
                // Landing back on the system's own step means "match system",
                // so the override is cleared rather than pinned to the same
                // number — otherwise the app would stop following iOS while
                // appearing to agree with it.
                let i = Int(value.rounded())
                settings.overrideIndex = (i == AppSettings.index(of: systemSize)) ? nil : i
            }
        )
    }

    /// Transfer size of the archive as installed. Empty when no manifest is
    /// present, rather than guessing a number.
    private var archiveSizeLabel: String {
        guard let m = DatabaseLocation.installedManifest(), m.compressedSize > 0 else { return "" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return " (\(f.string(fromByteCount: m.compressedSize)))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image("AppIconPreview")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            // Version on the name line, but set back in the same
                            // gray as the credits below so the name reads first.
                            (Text(AppInfo.displayName).font(.title3.weight(.semibold))
                             + Text(" \(AppInfo.version) (\(AppInfo.build))")
                                .font(.subheadline).foregroundStyle(.secondary))
                            Text(AppInfo.appCopyright)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(AppInfo.databaseCredit)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("App Font Size") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            // Fixed sizes: slider end-markers, not body text,
                            // so they must not scale with the value they set.
                            Text("A").font(.system(size: 13))
                            Slider(value: sizeSlider,
                                   in: 0...Double(AppSettings.steps.count - 1),
                                   step: 1)
                            Text("A").font(.system(size: 24))
                        }
                        .foregroundStyle(.secondary)

                        HStack {
                            Text(settings.isOverriding
                                 ? AppSettings.name(of: effectiveSize)
                                 : "Matching System")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if settings.isOverriding {
                                Button("Tap to Match System") { settings.matchSystem() }
                                    .font(.caption)
                            }
                        }

                        // Live sample: monospaced, as message bodies are.
                        Text("Sezam.Net  1989-1999\n  Aa Bb Cc  Čč Šš Žž Ćć Đđ\n  +----+----+")
                            .font(settings.messageFont)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    Button {
                        confirmRedownload = true
                    } label: {
                        Label("Re-download the Archive\(archiveSizeLabel)", systemImage: "arrow.clockwise")
                    }
                    .disabled(!bootstrap.canRedownload)

                    if !bootstrap.canRedownload, let next = bootstrap.redownloadAvailableAt {
                        Text("Available again \(next.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("The Archive is normally downloaded just once for offline "
                         + "access. Tap only if it appears corrupted or incomplete.")
                }

                // Last item in the panel: heading and text share one card.
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppInfo.archiveNoticeHeading)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Quotes added at display time; AppInfo keeps the
                        // notice verbatim as published on the site.
                        Text("\u{201C}" + AppInfo.archiveNotice + "\u{201D}")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Re-download the Archive?", isPresented: $confirmRedownload) {
                Button("Re-download", role: .destructive) { bootstrap.startRedownload() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The existing archive will be replaced. You will be shown the "
                     + "download size before anything is transferred.")
            }
        }
    }
}
