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

struct MessageListView: View {
    let topic: TopicSummary
    @State private var pager: MessagePager

    init(topic: TopicSummary, anchor: MessageAnchor? = nil) {
        self.topic = topic
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
                                parentID: pager.parentID(of: msg),
                                onJump: { target in jump(to: target, using: proxy) })
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
            .navigationTitle(topic.name)
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

    private func jump(to target: Int64, using proxy: ScrollViewProxy) {
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

private struct MessageCell: View {
    @State private var settings = AppSettings.shared
    let message: MessageRow
    var parentID: Int64?
    var onJump: (Int64) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(message.author).font(.caption.weight(.semibold))
                Text("#\(message.seq)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(message.displayDate).font(.caption2).foregroundStyle(.secondary)
            }
            if let reply = message.replyLabel {
                if let parentID {
                    Button { onJump(parentID) } label: {
                        Text(reply).font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                } else {
                    // Parent deleted or not yet paged in: show it, but do not
                    // dress it up as something that responds to a tap.
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
