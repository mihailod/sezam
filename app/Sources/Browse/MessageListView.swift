import SwiftUI

/// Pages messages a volume at a time, by `seq`, with no page numbers -- the
/// original site's pagination is replaced by continuous scrolling.
struct VolumeSeq: Hashable {
    let topicID: Int64
    let seq: Int
}

@MainActor
@Observable
final class MessagePager {
    private(set) var items: [MessageRow] = []
    private(set) var isLoading = false
    private(set) var reachedEnd = false

    /// Replies point backwards within the same volume (verified: 99.5% resolve
    /// there, and we always page forward from seq 0), so a parent is already
    /// loaded by the time its reply is on screen. The 2,005 archive-wide links
    /// whose parent was deleted simply never resolve, and render inert.
    private var rowID: [VolumeSeq: Int64] = [:]
    private var volumes: [TopicVolume] = []
    private var volumeIndex = 0
    private var lastSeq = 0
    private let pageSize = 60

    let topic: TopicSummary
    /// When set, the thread opens around this message instead of at the start.
    let anchor: MessageAnchor?
    private(set) var pendingScroll: Int64?
    private(set) var canLoadEarlier = false
    private var earliestVolumeIndex = 0
    private var earliestSeq = 0

    init(topic: TopicSummary, anchor: MessageAnchor? = nil) {
        self.topic = topic
        self.anchor = anchor
    }

    func consumePendingScroll() -> Int64? {
        defer { pendingScroll = nil }
        return pendingScroll
    }

    var totalMessages: Int { volumes.reduce(0) { $0 + $1.messages } }

    /// nil when the parent was deleted decades ago, or has not been paged in yet.
    func parentID(of message: MessageRow) -> Int64? {
        guard let seq = message.replySeq else { return nil }
        return rowID[VolumeSeq(topicID: message.topicID, seq: seq)]
    }

    /// Whether the hint is worth offering: the parent is in memory, or is still
    /// somewhere earlier in the thread and can be fetched on demand.
    ///
    /// Only when everything earlier has been read and the parent is still
    /// absent is it genuinely gone -- 2,005 of the archive's 399,442 replies
    /// point at a message that was deleted. Those are the only inert ones, and
    /// a thread that exhausts itself during a jump turns its hint grey by
    /// itself, because `canLoadEarlier` becomes false.
    func canJump(to message: MessageRow) -> Bool {
        guard message.replySeq != nil else { return false }
        return parentID(of: message) != nil || canLoadEarlier
    }

    /// Pages backwards until the parent is in memory, and answers with its row.
    ///
    /// Cheap in practice: replies point back a median of 5 messages and 99% of
    /// them within 180, so this is usually nothing or a single extra page. The
    /// pathological case in this archive is a reply 5,002 messages back, which
    /// is why it stops the moment a page adds nothing rather than trusting the
    /// loop to end on its own.
    func reveal(parentOf message: MessageRow) -> Int64? {
        guard let seq = message.replySeq else { return nil }
        let key = VolumeSeq(topicID: message.topicID, seq: seq)
        while rowID[key] == nil, canLoadEarlier {
            let before = items.count
            loadEarlier()
            if items.count == before { break }
        }
        return rowID[key]
    }

    func start() {
        guard volumes.isEmpty, !reachedEnd else { return }
        volumes = (try? BrowseRepository.volumes(family: topic.family, topic: topic.name)) ?? []
        if volumes.isEmpty { reachedEnd = true; return }

        if let anchor, let idx = volumes.firstIndex(where: { $0.id == anchor.topicID }) {
            // Start a little before the target so it lands in context, not at
            // the very top edge of an otherwise empty screen.
            volumeIndex = idx
            lastSeq = max(0, anchor.seq - 12)
            earliestVolumeIndex = idx
            earliestSeq = lastSeq + 1
            canLoadEarlier = idx > 0 || lastSeq > 0
            loadMore()
            pendingScroll = rowID[VolumeSeq(topicID: anchor.topicID, seq: anchor.seq)]
        } else {
            earliestSeq = 1
            loadMore()
        }
    }

    /// Walks backwards from the anchor, stepping into the previous volume when
    /// the current one is exhausted.
    func loadEarlier() {
        guard canLoadEarlier, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if earliestSeq <= 1 {
            guard earliestVolumeIndex > 0 else { canLoadEarlier = false; return }
            earliestVolumeIndex -= 1
            earliestSeq = Int.max
        }
        let vol = volumes[earliestVolumeIndex]
        let page = (try? BrowseRepository.messagesBefore(topicID: vol.id,
                                                         beforeSeq: earliestSeq,
                                                         limit: 40)) ?? []
        if page.isEmpty {
            if earliestVolumeIndex > 0 { earliestVolumeIndex -= 1; earliestSeq = Int.max }
            else { canLoadEarlier = false }
            return
        }
        for m in page { rowID[VolumeSeq(topicID: m.topicID, seq: m.seq)] = m.id }
        items.insert(contentsOf: page, at: 0)
        earliestSeq = page.first?.seq ?? 1
        canLoadEarlier = earliestVolumeIndex > 0 || earliestSeq > 1
    }

    func loadMore() {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }

        var added = 0
        // A volume may run out mid-page, so keep walking forward until the page
        // is filled or the volumes are exhausted.
        while added < pageSize, volumeIndex < volumes.count {
            let vol = volumes[volumeIndex]
            let page = (try? BrowseRepository.messages(topicID: vol.id,
                                                       afterSeq: lastSeq,
                                                       limit: pageSize - added)) ?? []
            if page.isEmpty {
                volumeIndex += 1
                lastSeq = 0
                continue
            }
            for m in page { rowID[VolumeSeq(topicID: m.topicID, seq: m.seq)] = m.id }
            items.append(contentsOf: page)
            added += page.count
            lastSeq = page.last?.seq ?? lastSeq
        }
        if volumeIndex >= volumes.count { reachedEnd = true }
    }
}

struct MessageAnchor: Hashable {
    let topicID: Int64
    let seq: Int
}

/// A tapped author name. Its own type rather than `UserItem`: a message row
/// knows only the username, so the profile has to be looked up on arrival.
struct AuthorLink: Hashable {
    let username: String
}

/// A thread to open, optionally at one message. Pushed by value like every
/// other screen, so the stack has exactly one declaration for it.
struct ThreadTarget: Hashable {
    let topic: TopicSummary
    var anchor: MessageAnchor?
}

struct MessageListView: View {
    let topic: TopicSummary
    /// The stack's path, so tapping a name can push while the name stays a
    /// plain button and the rest of the message stays inert.
    ///
    /// Handed over at construction rather than read from the environment: a
    /// pushed view inherits the environment of the *stack*, not of the view
    /// that declared the destination, so an `@Environment` lookup here found
    /// nothing and trapped as soon as a thread opened. As an argument, the
    /// compiler will not let that happen.
    let router: NavRouter
    @State private var pager: MessagePager

    init(topic: TopicSummary, anchor: MessageAnchor? = nil, router: NavRouter) {
        self.topic = topic
        self.router = router
        _pager = State(initialValue: MessagePager(topic: topic, anchor: anchor))
    }

    @State private var highlighted: Int64?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if pager.canLoadEarlier {
                    Button("Load earlier messages") { pager.loadEarlier() }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
                ForEach(pager.items) { msg in
                    MessageCell(message: msg,
                                canJump: pager.canJump(to: msg),
                                onJump: { jump(toParentOf: msg, using: proxy) },
                                onAuthor: { router.path.append(AuthorLink(username: $0)) })
                        .id(msg.id)
                        .listRowBackground(highlighted == msg.id
                                           ? Color.accentColor.opacity(0.15) : Color.clear)
                        .onAppear {
                            // Prefetch before the very bottom so scrolling stays smooth.
                            if msg.id == pager.items.suffix(8).first?.id { pager.loadMore() }
                        }
                }
                if !pager.reachedEnd {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            // The full path, not the bare topic name: a thread is reached from
            // a search hit and from a user's history as often as by drilling
            // down, and in those two the conference is nowhere else on screen.
            // The same bullet the rows use to join facts. A plain dot would be
            // ambiguous here: topic names carry their own dots, so PCUSER and
            // "tekst.procesori" would read as one three-part name.
            .navigationTitle("\(topic.family) · \(topic.name)")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                pager.start()
                if let target = pager.consumePendingScroll() {
                    // One runloop turn so the rows exist before scrolling to one.
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(target, anchor: .top)
                    highlighted = target
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation(.easeOut(duration: 0.5)) { highlighted = nil }
                }
            }
        }
    }

    /// Reads whatever earlier messages it takes to put the parent on screen,
    /// then scrolls to it. Doing this on the tap rather than up front is what
    /// lets the hint be live from the moment the thread opens: arriving from a
    /// search hit or a profile starts the reader mid-thread, where the parent
    /// is almost never already in memory.
    private func jump(toParentOf message: MessageRow, using proxy: ScrollViewProxy) {
        guard let target = pager.reveal(parentOf: message) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(target, anchor: .top)
            highlighted = target
        }
        // Fade the highlight so the eye lands on the right message, then settles.
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.5)) { highlighted = nil }
        }
    }
}

/// The profile behind an author's name. Most names resolve; 83 of the 3,901
/// people who ever posted never appeared in the member directory, and for those
/// this says so rather than opening a profile with nothing in it.
struct AuthorProfileView: View {
    let username: String
    @State private var user: UserItem?
    @State private var searched = false

    var body: some View {
        Group {
            if let user {
                UserMessagesView(user: user)
            } else if searched {
                NoProfileView(username: username)
            } else {
                ProgressView()
            }
        }
        .task {
            guard !searched else { return }
            // A member first; failing that an author with no directory entry,
            // whose messages are still worth opening.
            user = (try? UsersRepository.user(username: username))
                ?? (try? UsersRepository.unlistedAuthor(username: username))
            searched = true
        }
    }
}

/// Shown for a name with no directory entry, whether it was tapped in a thread
/// or in the N/A section of the directory.
struct NoProfileView: View {
    let username: String

    var body: some View {
        ContentUnavailableView {
            Label(username, systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("This user wrote messages, but was not found in the member "
                 + "directory (removed?). No user info to show.")
        }
    }
}

private struct MessageCell: View {
    @State private var settings = AppSettings.shared
    let message: MessageRow
    var canJump = false
    var onJump: () -> Void = { }
    var onAuthor: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // A Button rather than a NavigationLink: a link inside a list
                // row makes the entire row activate it, so a tap anywhere in
                // the message opened the author's page. Only the name is
                // tappable now, and the body is inert again.
                Button { onAuthor(message.author) } label: {
                    Text(message.author).font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                Text("#\(message.seq)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(message.displayDate).font(.caption2).foregroundStyle(.secondary)
            }
            if let reply = message.replyLabel {
                if canJump {
                    Button(action: onJump) {
                        Text(reply).font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                } else {
                    // The parent was deleted decades ago: show the hint, but do
                    // not dress it up as something that responds to a tap.
                    Text(reply).font(.caption2).foregroundStyle(.secondary)
                }
            }
            // Monospaced: these messages are full of box-drawing art and
            // hand-aligned columns that a proportional font would destroy.
            Text(message.displayBody)
                .font(settings.messageFont)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}
