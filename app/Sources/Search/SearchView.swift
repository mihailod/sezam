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

    /// Kept across searches for the life of the tab: someone reading oldest
    /// first is still reading oldest first after refining the words.
    ///
    /// Most Replies by default: in an archive of conversations, the messages
    /// that started one are usually the ones worth landing on first.
    private(set) var sort: MessageSearchSort = .mostReplies

    /// Bumped by every search. Queries run off the main actor, so an older one
    /// can finish after a newer one; only the newest may publish results.
    private var generation = 0

    /// Re-runs the whole search rather than refetching only the messages.
    ///
    /// Refetching alone would race a keystroke: if a new query were still in
    /// flight, a messages-only reload would publish results for the *old*
    /// words and then discard the new search as superseded. Going through
    /// `run` lets the one generation counter sort that out. The people and
    /// counts it also re-reads come back identical, so nothing visible moves.
    func setSort(_ new: MessageSearchSort) async {
        guard new != sort else { return }
        sort = new
        await run(query)
    }

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
        let limit = pageSize, order = sort
        let (foundPeople, foundMessages, totals) = await Task.detached(priority: .userInitiated) {
            ((try? SearchRepository.people(matching: expr, limit: 8)) ?? [],
             (try? SearchRepository.messages(matching: expr, sort: order,
                                             limit: limit, offset: 0)) ?? [],
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
        let gen = generation, offset = messages.count, limit = pageSize, order = sort
        Task {
            let next = await Task.detached(priority: .userInitiated) {
                (try? SearchRepository.messages(matching: expr, sort: order,
                                                limit: limit, offset: offset)) ?? []
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
            .searchable(text: $controller.query,
                        placement: Self.searchPlacement,
                        prompt: "Search messages and people")
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

    /// On iPad the default placement is a compact field in the toolbar beside
    /// the tab bar -- an idle affordance that expands only once it has focus,
    /// and narrow enough at rest that the prompt truncates to "Search
    /// messages...". The drawer is what the phone already uses: a full-width
    /// field under the title, which is both the larger target and the one
    /// that shows what you can search without being tapped first.
    private static var searchPlacement: SearchFieldPlacement {
        Device.isPad ? .navigationBarDrawer(displayMode: .always) : .automatic
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
            Section {
                ForEach(controller.messages) { hit in
                    NavigationLink(value: ThreadTarget(
                        topic: TopicSummary(family: hit.family, name: hit.topic,
                                            messages: 0, firstPost: nil, lastPost: nil),
                        anchor: MessageAnchor(topicID: hit.topicID, seq: hit.seq))) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(hit.author).font(.caption.weight(.semibold))
                                Text(hit.repliesLabel)
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(hit.displayDate).font(.caption2).foregroundStyle(.secondary)
                            }
                            // Where the message lives, straight under who wrote it and
                            // in the same tint as on a member's message list, so a hit
                            // reads source-first the way those rows do. It used to
                            // trail the snippet in faint grey, easy to miss.
                            Text(hit.location)
                                .font(.caption2).foregroundStyle(.tint)
                                .lineLimit(1)
                            Text(SearchSnippet.make(from: hit.body, terms: controller.terms))
                                .font(.footnote)
                                .lineLimit(3)
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
            } header: {
                // In this section's header rather than the toolbar, because it
                // orders only these rows. Up in the bar it would read as sorting
                // the whole screen, People included, which it does not.
                HStack {
                    Text(Self.hits("Messages", controller.messagesTotal))
                    Spacer()
                    SortMenu(selection: Binding(
                        get: { controller.sort },
                        set: { new in Task { await controller.setSort(new) } }))
                        .textCase(nil)
                }
            }
        }
        // A fresh identity per order, so a re-sorted list opens at the top
        // instead of holding the scroll offset of rows that have all moved.
        .id(controller.sort)
    }
}

extension MessageSearchSort: SortOption {}

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
