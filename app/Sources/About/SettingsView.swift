import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    /// The size actually in effect: the system's when nothing is overridden,
    /// so the slider starts where the user already is rather than snapping.
    @Environment(\.dynamicTypeSize) private var effectiveSize
    @Environment(\.systemTypeSize) private var systemSize

    private var sizeSlider: Binding<Double> {
        Binding(
            get: { Double(settings.overrideIndex ?? AppSettings.index(of: systemSize)) },
            set: { value in setStep(Int(value.rounded())) }
        )
    }

    /// Landing back on the system's own step means "match system", so the
    /// override is cleared rather than pinned to the same number —
    /// otherwise the app would stop following iOS while appearing to agree
    /// with it. Shared by the slider and the two tap-to-nudge "A"s.
    private func setStep(_ i: Int) {
        settings.overrideIndex = (i == AppSettings.index(of: systemSize)) ? nil : i
    }

    private func nudge(by delta: Int) {
        let current = settings.overrideIndex ?? AppSettings.index(of: systemSize)
        let clamped = max(0, min(AppSettings.steps.count - 1, current + delta))
        setStep(clamped)
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
                            // Also tappable, each moving the size by one notch.
                            Button { nudge(by: -1) } label: {
                                Text("A").font(.system(size: 13))
                            }
                            Slider(value: sizeSlider,
                                   in: 0...Double(AppSettings.steps.count - 1),
                                   step: 1)
                            Button { nudge(by: 1) } label: {
                                Text("A").font(.system(size: 24))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)

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
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AppInfo.credits, id: \.self) { line in
                            Text(line)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                // Heading and text share one card.
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

                // The epigraphs close the panel.
                ForEach(AppInfo.epigraphs) { epigraph in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\u{201C}" + epigraph.quote + "\u{201D}")
                                .font(.callout.italic())
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\u{2014} " + epigraph.author)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
