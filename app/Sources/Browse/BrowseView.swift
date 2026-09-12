import SwiftUI

struct BrowseView: View {
    @State private var families: [ConferenceFamily] = []
    @State private var router = NavRouter()
    @State private var error: String?
    @Bindable private var sort = BrowseSortSelection.shared

    /// 27 rows: cheap enough to re-sort on every render, unlike the Users list.
    private var sorted: [ConferenceFamily] { sort.value.apply(families) }

    private let num: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(sorted) { fam in
                    NavigationLink(value: fam) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fam.family).font(.headline)
                            Text("\(count(fam.messages)) messages · \(fam.topics) topics · \(fam.span)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ArchiveSortMenu(sort: $sort.value)
                }
            }
            .archiveDestinations(router)
            .overlay {
                if let error {
                    ContentUnavailableView("Could not read the archive",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if families.isEmpty {
                    ProgressView()
                }
            }
            .task {
                do { families = try BrowseRepository.families() }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func count(_ n: Int) -> String { num.string(from: NSNumber(value: n)) ?? "\(n)" }

    /// "Sezam 1989–1999", as one plain string so it renders at the same size
    /// as "Sezam Users" and "Search Sezam". A navigation title cannot mix two
    /// sizes, and the iOS 26 view that could was what made the span smaller;
    /// years are short enough not to need it. The rows below still carry the
    /// month-precision spans.
    private var title: String { span.map { "Sezam \($0)" } ?? "Sezam" }

    /// "1989–1999": what the whole archive covers, taken from the rows rather
    /// than hard-coded. Nil until the rows are in, so it never flashes a
    /// half-title.
    ///
    /// min/max over the stored ISO timestamps, which sort in date order, so
    /// the year comes off the genuinely earliest and latest message.
    private var span: String? {
        guard let first = families.compactMap(\.firstPost).min()?.prefix(4),
              let last = families.compactMap(\.lastPost).max()?.prefix(4) else { return nil }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    /// Rendered as a caption row rather than `navigationSubtitle`, which is
    /// iOS 26-only and would show nothing on the iOS 17 deployment target.
    /// Empty until the rows are in, so it never flashes a zero.
    private var subtitle: String {
        guard !families.isEmpty else { return "" }
        let messages = families.reduce(0) { $0 + $1.messages }
        // Summing the rows' own figures, so the total always agrees with what
        // the rows below say. A family counts a topic spread over several
        // volumes once, and no topic spans two families.
        let topics = families.reduce(0) { $0 + $1.topics }
        return "\(families.count) conferences · \(count(topics)) topics · \(count(messages)) messages"
    }
}
