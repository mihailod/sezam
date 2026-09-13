import SwiftUI

struct TopicListView: View {
    /// The conference name alone: the row that pushes this screen has a whole
    /// `ConferenceFamily`, but a thread's title bar can only offer the name, and
    /// this view never needed more than that.
    let family: String
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
        .navigationTitle(family)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(selection: $sort.value)
            }
        }
        .overlay { if topics.isEmpty { ProgressView() } }
        .task {
            topics = (try? BrowseRepository.topics(in: family)) ?? []
        }
    }

    private func count(_ n: Int) -> String { num.string(from: NSNumber(value: n)) ?? "\(n)" }
}
