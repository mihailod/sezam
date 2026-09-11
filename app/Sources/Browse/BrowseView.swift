import SwiftUI

struct BrowseView: View {
    @State private var families: [ConferenceFamily] = []
    @State private var error: String?

    private let num: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(families) { fam in
                    NavigationLink(value: fam) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fam.family).font(.headline)
                            Text("\(count(fam.messages)) messages · \(fam.topics) topics · \(fam.yearSpan)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                // The large title with the span a size down. A navigation title
                // is a plain string and cannot mix sizes; iOS 26 lets a view
                // stand in for the large title, while the string above still
                // supplies the collapsed title and the back button. Earlier
                // systems show that string at full size.
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .largeTitle) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Sezam").font(.largeTitle.bold())
                            if let span { Text(span).font(.title2.bold()) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationDestination(for: ConferenceFamily.self) { TopicListView(family: $0) }
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

    /// "Sezam 1989–1999": the span the whole archive covers, taken from the
    /// rows rather than hard-coded, and written with the same en dash as the
    /// rows' own spans. Plain "Sezam" until the rows are in.
    private var title: String { span.map { "Sezam \($0)" } ?? "Sezam" }

    private var span: String? {
        guard let first = families.compactMap(\.firstYear).min(),
              let last = families.compactMap(\.lastYear).max() else { return nil }
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
