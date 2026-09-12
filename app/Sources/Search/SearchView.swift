import SwiftUI

@MainActor
@Observable
final class SearchController {
    var query = ""
    private(set) var people: [UserItem] = []
    private(set) var messages: [MessageHit] = []
    private(set) var terms: [String] = []
    private(set) var isSearching = false
    private(set) var reachedEnd = true
    /// Total matches, which can far exceed what is listed: People shows the
    /// top 8, Messages loads a page at a time.
    private(set) var peopleTotal = 0
    private(set) var messagesTotal = 0
    private(set) var expression: String?

    private let pageSize = 40
    private var isLoadingMore = false

    /// Bumped by every search. Queries run off the main actor, so an older one
    /// can finish after a newer one; only the newest may publish results.
    private var generation = 0

    /// The query runs off the main actor. A common prefix ranks hundreds of
    /// thousands of rows -- "beog*" matches 435k messages, ~260 ms on a Mac
    /// and slower on a phone -- and on the main thread that froze the keyboard
    /// mid-word.
    func run(_ raw: String) async {
        generation += 1
        let gen = generation
        guard let expr = SearchQuery.ftsExpression(from: raw) else {
            people = []; messages = []; terms = []; expression = nil; reachedEnd = true
            peopleTotal = 0; messagesTotal = 0
            isSearching = false
            return
        }
        isSearching = true
        let limit = pageSize
        let (foundPeople, foundMessages, totals) = await Task.detached(priority: .userInitiated) {
            ((try? SearchRepository.people(matching: expr, limit: 8)) ?? [],
             (try? SearchRepository.messages(matching: expr, limit: limit, offset: 0)) ?? [],
             SearchRepository.hitCounts(matching: expr))
        }.value
        guard gen == generation else { return }     // superseded by a newer keystroke
        expression = expr
        terms = SearchQuery.highlightTerms(from: raw)
        people = foundPeople
        messages = foundMessages
        peopleTotal = totals.people
        messagesTotal = totals.messages
        reachedEnd = foundMessages.count < limit
        isSearching = false
    }

    func loadMore() {
        guard let expr = expression, !reachedEnd, !isLoadingMore else { return }
        isLoadingMore = true
        let gen = generation, offset = messages.count, limit = pageSize
        Task {
            let next = await Task.detached(priority: .userInitiated) {
                (try? SearchRepository.messages(matching: expr, limit: limit, offset: offset)) ?? []
            }.value
            isLoadingMore = false
            guard gen == generation else { return } // a new search replaced this list
            messages.append(contentsOf: next)
            if next.count < limit { reachedEnd = true }
        }
    }
}

struct SearchView: View {
    @State private var controller = SearchController()
    @State private var router = NavRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            Group {
                if controller.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchHelpView()
                } else if controller.messages.isEmpty && controller.people.isEmpty {
                    if controller.isSearching {
                        ProgressView()
                    } else {
                        ContentUnavailableView.search(text: controller.query)
                    }
                } else {
                    results
                }
            }
            .navigationTitle("Search Sezam")
            .archiveDestinations(router)
            .searchable(text: $controller.query, prompt: Self.prompt)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .task(id: controller.query) {
            // Debounce so a 572k-row index is not queried on every keystroke.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await controller.run(controller.query)
        }
    }

    /// The iPad puts the search field in the toolbar at a fixed compact width,
    /// where the phone's prompt truncates to "Search messages...". A shorter
    /// one that still names both things you can search fits whole.
    private static var prompt: String {
        Device.isPad ? "Messages, people" : "Search messages and people"
    }

    /// "People (1 hit)", "Messages (254,701 hits)".
    private static func hits(_ title: String, _ n: Int) -> String {
        "\(title) (\(n.formatted()) \(n == 1 ? "hit" : "hits"))"
    }

    private var results: some View {
        List {
            if !controller.people.isEmpty {
                Section(Self.hits("People", controller.peopleTotal)) {
                    ForEach(controller.people) { person in
                        NavigationLink(value: person) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(person.username).font(.subheadline.weight(.semibold))
                                    if person.messageCount > 0 {
                                        Text("\(person.messageCount) messages")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                // The index matches on the real name too, so a
                                // hit often makes sense only once it is shown.
                                if let name = person.fullName, !name.isEmpty {
                                    Text(name).font(.caption).foregroundStyle(.primary.opacity(0.8))
                                }
                                if !person.subtitle.isEmpty {
                                    Text(person.subtitle).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Section(Self.hits("Messages", controller.messagesTotal)) {
                ForEach(controller.messages) { hit in
                    NavigationLink(value: ThreadTarget(
                        topic: TopicSummary(family: hit.family, name: hit.topic,
                                            messages: 0, firstYear: nil, lastYear: nil),
                        anchor: MessageAnchor(topicID: hit.topicID, seq: hit.seq))) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(hit.author).font(.caption.weight(.semibold))
                                Spacer()
                                Text(hit.displayDate).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(SearchSnippet.make(from: hit.body, terms: controller.terms))
                                .font(.footnote)
                                .lineLimit(3)
                            Text(hit.location).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        if hit.id == controller.messages.suffix(6).first?.id { controller.loadMore() }
                    }
                }
                if !controller.reachedEnd {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
    }
}

// MessageDetailView removed: a hit now opens the real thread, which shows
// the message in its conversation rather than in isolation.

private struct SearchHelpView: View {
    @State private var counts = ArchiveCounts(messages: 0, users: 0)

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()
    private func n(_ v: Int) -> String {
        Self.decimal.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private let examples: [(String, String)] = [
        ("amiga",               "every message or user info containing the word"),
        ("amiga atari",         "messages or user infos containing both words"),
        ("\"pc press\"",        "an exact phrase, in quotes"),
        ("author:dejanr modem", "only that author's messages"),
        ("Ristanović",          "messages by anyone with that name, and mentions of it"),
    ]

    var body: some View {
        List {
            Section {
                Text(counts.messages > 0
                     ? "Search \(n(counts.messages)) messages and \(n(counts.users)) "
                       + "people by username, real name, city or company."
                     : "Search the message archive and every registered user by "
                       + "username, real name, city or company.")
                    .font(.callout)
            }
            Section("Examples") {
                ForEach(examples, id: \.0) { ex in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.0).font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.tint)
                        Text(ex.1).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }
            Section("Serbian letters") {
                Text("čćšž work as expected (citanje finds čitanje, etc.) and đubre, "
                     + "djubre and dubre all return the same results")
                    .font(.callout)
            }
        }
        .task { counts = SearchRepository.counts() }
    }
}
