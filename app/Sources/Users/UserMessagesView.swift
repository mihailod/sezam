import SwiftUI

@MainActor
@Observable
final class AuthorMessagePager {
    private(set) var items: [AuthorMessage] = []
    private(set) var reachedEnd = false
    private var isLoading = false
    private var lastID: Int64 = 0
    private let pageSize = 50
    let user: UserItem

    init(user: UserItem) { self.user = user }

    func loadMore() {
        guard let authorID = user.authorID, !isLoading, !reachedEnd else {
            if user.authorID == nil { reachedEnd = true }
            return
        }
        isLoading = true
        defer { isLoading = false }
        let page = (try? UsersRepository.messages(authorID: authorID,
                                                  afterID: lastID,
                                                  limit: pageSize)) ?? []
        items.append(contentsOf: page)
        lastID = page.last?.id ?? lastID
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

            Section(user.messageCount > 0 ? "\(user.messageCount) messages" : "Messages") {
                if pager.items.isEmpty && pager.reachedEnd {
                    Text("This user never posted a message.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(pager.items) { msg in
                    NavigationLink(value: ThreadTarget(
                        topic: TopicSummary(family: msg.family, name: msg.topic,
                                            messages: 0, firstYear: nil, lastYear: nil),
                        anchor: MessageAnchor(topicID: msg.topicID, seq: msg.seq))) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(msg.location).font(.caption2).foregroundStyle(.tint)
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
        .task { if pager.items.isEmpty { pager.loadMore() } }
    }

    private var joinedLine: String {
        let joined = user.joinedISO.map { String($0.prefix(10)) } ?? "—"
        let seen = user.lastSeenISO.map { String($0.prefix(10)) } ?? "—"
        return "Joined \(joined) · last seen \(seen)"
    }
}
