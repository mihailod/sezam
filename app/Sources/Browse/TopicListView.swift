import SwiftUI

struct TopicListView: View {
    let family: ConferenceFamily
    @State private var topics: [TopicSummary] = []
    @Bindable private var sort = BrowseSortSelection.shared

    /// Sorted here rather than in the query: 463 topics at most, and the
    /// re-sort has to happen on every menu tap anyway.
    private var sorted: [TopicSummary] { sort.value.apply(topics) }

    private let num: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    var body: some View {
        List {
            ForEach(sorted) { topic in
                NavigationLink(value: ThreadTarget(topic: topic)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.name).font(.body)
                        Text("\(count(topic.messages)) messages · \(topic.span)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(family.family)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ArchiveSortMenu(sort: $sort.value)
            }
        }
        .overlay { if topics.isEmpty { ProgressView() } }
        .task {
            topics = (try? BrowseRepository.topics(in: family.family)) ?? []
        }
    }

    private func count(_ n: Int) -> String { num.string(from: NSNumber(value: n)) ?? "\(n)" }
}
