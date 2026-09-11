import SwiftUI

struct TopicListView: View {
    let family: ConferenceFamily
    @State private var topics: [TopicSummary] = []

    private let num: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    var body: some View {
        List {
            ForEach(topics) { topic in
                NavigationLink(value: topic) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.name).font(.body)
                        Text("\(count(topic.messages)) messages · \(topic.yearSpan)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(family.family)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: TopicSummary.self) { MessageListView(topic: $0) }
        .overlay { if topics.isEmpty { ProgressView() } }
        .task {
            topics = (try? BrowseRepository.topics(in: family.family)) ?? []
        }
    }

    private func count(_ n: Int) -> String { num.string(from: NSNumber(value: n)) ?? "\(n)" }
}
