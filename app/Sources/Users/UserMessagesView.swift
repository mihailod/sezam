import SwiftUI

/// Which end of an author's history to read from -- across the whole archive,
/// not within each topic. Picks the direction of the chronological walk.
enum AuthorMessageOrder: String, CaseIterable, Identifiable {
    // Declaration order is menu order, matching the thread sort menu.
    case oldest, newest, mostReplies
    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest:      return "Newest"
        case .oldest:      return "Oldest"
        case .mostReplies: return "Most Replies"
        }
    }

    /// The order spelled out after the count in the section header, so the
    /// list says how it is sorted without opening the menu.
    var headerPhrase: String {
        switch self {
        case .newest:      return "newest first"
        case .oldest:      return "oldest first"
        case .mostReplies: return "most replies"
        }
    }

    /// Where the walk begins: past the last message, or before the first.
    var startCursor: (epoch: Int64, id: Int64) {
        self == .newest ? (.max, .max) : (.min, .min)
    }
}

@MainActor
@Observable
final class AuthorMessagePager {
    private(set) var items: [AuthorMessage] = []
    private(set) var reachedEnd = false
    private(set) var order: AuthorMessageOrder = .oldest
    private var isLoading = false
    private var cursor = AuthorMessageOrder.oldest.startCursor
    /// How far Most Replies has read. That order has no cursor to key on, and
    /// needs none: it is one author's messages, and the busiest author in the
    /// archive (15,939 messages) sorts in 11 ms at any offset.
    private var offset = 0
    private let pageSize = 50
    let user: UserItem

    init(user: UserItem) { self.user = user }

    /// Starts the walk again from the other end. Nothing is re-sorted in
    /// memory: only the pages already read are dropped, and the same index is
    /// walked the other way.
    func setOrder(_ new: AuthorMessageOrder) {
        guard new != order else { return }
        order = new
        items = []
        reachedEnd = false
        cursor = new.startCursor
        offset = 0
        loadMore()
    }

    func loadMore() {
        guard let authorID = user.authorID, !isLoading, !reachedEnd else {
            if user.authorID == nil { reachedEnd = true }
            return
        }
        isLoading = true
        defer { isLoading = false }
        let page: [AuthorMessage]
        if order == .mostReplies {
            page = (try? UsersRepository.mostRepliedMessages(authorID: authorID,
                                                             limit: pageSize,
                                                             offset: offset)) ?? []
            offset += page.count
        } else {
            page = (try? UsersRepository.messages(authorID: authorID,
                                                  afterEpoch: cursor.epoch,
                                                  afterID: cursor.id,
                                                  limit: pageSize,
                                                  newestFirst: order == .newest)) ?? []
            if let last = page.last { cursor = (last.epoch, last.id) }
        }
        items.append(contentsOf: page)
        if page.count < pageSize { reachedEnd = true }
    }
}

struct UserMessagesView: View {
    let user: UserItem
    @State private var pager: AuthorMessagePager

    init(user: UserItem) {
        self.user = user
        _pager = State(initialValue: AuthorMessagePager(user: user))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    if user.isListed {
                        if let n = user.fullName, !n.isEmpty {
                            Text(n).font(.headline)
                        }
                        if !user.subtitle.isEmpty {
                            Text(user.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(joinedLine).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        // For these 83 the directory holds nothing at all, so
                        // the header says so and the messages below carry on
                        // exactly as they do for a member.
                        Text("This user wrote messages, but was not found in the "
                             + "member directory (removed?). No user info to show.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }

            Section(user.messageCount > 0
                    ? "\(user.messageCount) messages · \(pager.order.headerPhrase)"
                    : "Messages") {
                if pager.items.isEmpty && pager.reachedEnd {
                    Text("This user never posted a message.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(pager.items) { msg in
                    NavigationLink(value: ThreadTarget(
                        topic: TopicSummary(family: msg.family, name: msg.topic,
                                            messages: 0, firstPost: nil, lastPost: nil),
                        anchor: MessageAnchor(topicID: msg.topicID, seq: msg.seq))) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(msg.location).font(.caption2).foregroundStyle(.tint)
                                    .lineLimit(1)
                                Text(ReplyCount.label(msg.replies))
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize()
                                Spacer()
                                Text(msg.displayDate).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(msg.preview).font(.footnote).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        if msg.id == pager.items.suffix(6).first?.id { pager.loadMore() }
                    }
                }
                if !pager.reachedEnd {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .navigationTitle(user.username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if user.messageCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Buttons rather than a Picker, as on the Users list: a
                        // Section around a Picker does not render its header
                        // here, so the checkmark is drawn by hand.
                        Section("Sort by:") {
                            ForEach(AuthorMessageOrder.allCases) { option in
                                Button {
                                    pager.setOrder(option)
                                } label: {
                                    if pager.order == option {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(pager.order.label, systemImage: "arrow.up.arrow.down")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                    }
                }
            }
        }
        .task { if pager.items.isEmpty { pager.loadMore() } }
    }

    private var joinedLine: String {
        let joined = ArchiveDate.day(user.joinedISO) ?? "—"
        let seen = ArchiveDate.day(user.lastSeenISO) ?? "—"
        return "Joined \(joined) · last seen \(seen)"
    }
}
