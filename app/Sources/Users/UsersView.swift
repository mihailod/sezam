import SwiftUI

struct UsersView: View {
    @State private var all: [UserItem] = []
    @State private var sort: UserSort = .username
    @State private var loaded = false

    /// Cached, not computed: grouping and sorting 8,105 users on every body
    /// evaluation is far too much work to repeat per render.
    @State private var sections: [UserSection] = []

    @State private var filter = UserFilter()
    @State private var showFilter = false
    @State private var cityFacets: [Facet] = []
    @State private var companyFacets: [Facet] = []
    @State private var yearFacets: [Facet] = []
    @State private var regionFacets: [Facet] = []

    /// Everything the filter admits. Computed once per filter change and reused
    /// by the sections, the subtitle and the sheet's live match count.
    @State private var visible: [UserItem] = []

    private func rebuildSections() {
        let present = visible.filter { !sort.isMissing($0) }
        let missing = visible.filter { sort.isMissing($0) }

        // Decorate once. sortKey folds per character through ICU, so calling it
        // from inside the comparator would repeat that work O(n log n) times.
        struct Keyed {
            let bucket: String
            let key: String
            let name: String
            let user: UserItem
        }
        var groups: [String: [Keyed]] = [:]
        groups.reserveCapacity(40)
        for u in present {
            groups[sort.bucket(u), default: []].append(
                Keyed(bucket: sort.bucket(u), key: sort.sortKey(u),
                      name: SerbianLatin.key(u.username), user: u))
        }

        // Ordered by the sort's own bucket ranking, not alphabetically:
        // "#" leads, "—" trails, and magnitude buckets run 1k+ down to 0.
        var result = groups.keys
            .sorted { (sort.bucketRank($0), $0) < (sort.bucketRank($1), $1) }
            .map { key in
                UserSection(id: key,
                            title: sort.bucketTitle(key),
                            users: groups[key]!
                                .sorted { ($0.key, $0.name) < ($1.key, $1.name) }
                                .map(\.user))
            }
        if !missing.isEmpty {
            // Keys computed once, for the reason given above. Sorting by
            // Company leaves 6,488 users here; folding inside the comparator
            // was 194 ms of a 245 ms re-sort in a Debug build.
            let ordered = missing.map { (SerbianLatin.key($0.username), $0) }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
            result.append(UserSection(id: "—", title: "—", users: ordered))
        }
        sections = result
    }

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    /// Cached like `sections`: it scans all 8,105 users, which is not work to
    /// repeat on every render.
    ///
    /// A caption row rather than `navigationSubtitle` (iOS 26-only), and it
    /// survives where a long large title would silently truncate.
    @State private var subtitle: String = ""

    private func rebuildSubtitle() {
        guard !all.isEmpty else { subtitle = ""; return }
        let n = Self.decimal.string(from: NSNumber(value: visible.count)) ?? "\(visible.count)"
        let posted = visible.filter { $0.messageCount > 0 }.count
        let p = Self.decimal.string(from: NSNumber(value: posted)) ?? "\(posted)"
        // "3,818 posted messages" would read as a message count; it is the
        // number of users who ever wrote one.
        let base = "\(n) users · \(p) wrote messages"
        guard !filter.isEmpty else { subtitle = base; return }
        let total = Self.decimal.string(from: NSNumber(value: all.count)) ?? "\(all.count)"
        subtitle = "\(base) · filtered from \(total)"
    }

    /// Re-applies the filter and everything derived from it.
    private func rebuildAll() {
        visible = filter.isEmpty ? all : all.filter(filter.matches)
        rebuildSubtitle()
        rebuildSections()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.users) { user in
                                NavigationLink(value: user) { UserRow(user: user, sort: sort) }
                            }
                        } header: {
                            // Count in the header only -- the index bar keeps the
                            // bare letter, since it must stay one glyph wide.
                            Text("\(section.title) (\(section.users.count))")
                        }
                        .id(section.id)
                    }
                }
                .listStyle(.plain)
                .overlay(alignment: .trailing) {
                    if sections.count > 1 {
                        SectionIndexBar(titles: sections.map(\.id)) { title in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(title, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sezam Users")
            .navigationDestination(for: UserItem.self) { UserMessagesView(user: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilter = true } label: {
                        Label("Filter", systemImage: filter.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    // Disabled until the background build of the filter lists
                    // finishes. It also makes body read them: without a read here
                    // SwiftUI never re-renders when they arrive, and the sheet keeps
                    // the empty lists it was handed at the render before the build.
                    .disabled(cityFacets.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Buttons rather than a Picker: a Section containing a
                        // Picker does not render its header here, with or
                        // without .inline, so the checkmark is drawn by hand.
                        Section("Sort by:") {
                            ForEach(UserSort.allCases) { option in
                                Button {
                                    sort = option
                                } label: {
                                    if sort == option {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(sort.label, systemImage: "arrow.up.arrow.down")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                    }
                }
            }
            .overlay {
                if !loaded {
                    ProgressView()
                } else if visible.isEmpty {
                    ContentUnavailableView {
                        Label("No matching users", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No one in the archive matches every filter.")
                    } actions: {
                        Button("Clear Filters") { filter = UserFilter() }
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                UserFilterSheet(cityFacets: cityFacets,
                                companyFacets: companyFacets,
                                yearFacets: yearFacets,
                                regionFacets: regionFacets,
                                matchCount: visible.count,
                                filter: $filter)
            }
            .task {
                guard !loaded else { return }
                all = (try? UsersRepository.allUsers()) ?? []
                rebuildAll()
                loaded = true
                // The filter lists are only needed once the sheet opens, so they
                // are built after the list is on screen, off the main thread.
                // Built first, they were ~185 ms of the first tap in a Debug
                // build -- three quarters of the wait before the list appeared.
                let users = all
                let (cities, companies, years, regions) = await Task.detached(priority: .utility) {
                    (UserFacets.build(users, field: .city),
                     UserFacets.build(users, field: .company),
                     UserFacets.years(users),
                     UserFacets.buildRegions(users))
                }.value
                cityFacets = cities
                companyFacets = companies
                yearFacets = years
                regionFacets = regions
            }
            .onChange(of: sort) { _, _ in rebuildSections() }
            .onChange(of: filter) { _, _ in rebuildAll() }
        }
    }
}

private struct UserRow: View {
    let user: UserItem
    let sort: UserSort

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(user.username).font(.subheadline.weight(.semibold))
                if user.messageCount > 0 {
                    Text("\(user.messageCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if sort.indexesByYear, let v = sort.value(user) {
                    Text(String(v.prefix(10))).font(.caption2).foregroundStyle(.secondary)
                }
                // Message count already sits beside the username, so the
                // numeric sort needs nothing extra on the right.
            }
            if let name = user.fullName, !name.isEmpty {
                Text(name).font(.caption).foregroundStyle(.primary.opacity(0.8))
            }
            if !user.subtitle.isEmpty {
                Text(user.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
