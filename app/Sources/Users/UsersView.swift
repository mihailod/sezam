import SwiftUI

struct UsersView: View {
    @State private var all: [UserItem] = []
    @State private var router = NavRouter()
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
    /// Authors with no directory entry, shown in their own last section.
    @State private var unlisted: [UserItem] = []
    /// Those of them the search box still admits.
    @State private var unlistedVisible: [UserItem] = []

    @State private var query = ""
    /// The query folded and split, so a row is tested against ready tokens
    /// rather than re-folding the query 8,105 times per keystroke.
    @State private var queryTokens: [String] = []

    /// Per user, everything searchable folded into one string, built once when
    /// the directory loads. Folding is ICU work: doing it per row per keystroke
    /// is what makes an in-memory search feel slow.
    @State private var haystack: [Int64: String] = [:]
    /// Usernames pre-folded for the sort, for the same reason.
    @State private var nameKeys: [Int64: String] = [:]

    /// Every token has to appear somewhere in the row, so "marko beograd"
    /// narrows rather than widens.
    private func matchesQuery(_ u: UserItem) -> Bool {
        guard !queryTokens.isEmpty else { return true }
        guard let hay = haystack[u.id] else { return false }
        return queryTokens.allSatisfy(hay.contains)
    }

    /// Everything the filter admits. Computed once per filter change and reused
    /// by the sections, the subtitle and the sheet's live match count.
    @State private var visible: [UserItem] = []

    private func rebuildSections() {
        // Sorting by message count is the one ordering where the unlisted
        // authors have the value being sorted on, so there they mix into the
        // magnitude buckets instead of sitting apart at the end.
        let mixesIn = filter.isEmpty && sort.indexesByMagnitude
        let rows = mixesIn ? visible + unlistedVisible : visible
        let present = rows.filter { !sort.isMissing($0) }
        let missing = rows.filter { sort.isMissing($0) }

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
                      name: nameKeys[u.id] ?? SerbianLatin.key(u.username), user: u))
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
            let ordered = missing.map { (nameKeys[$0.id] ?? SerbianLatin.key($0.username), $0) }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
            result.append(UserSection(id: "—", title: "—", users: ordered))
        }
        // People who posted but never appeared in the directory. Last, and only
        // with no filter on: they have no city, company or join year, so every
        // filter would exclude them anyway, and counting them would inflate the
        // Not Specified figure in each filter list.
        if filter.isEmpty, !unlistedVisible.isEmpty, !mixesIn {
            result.append(UserSection(id: "N/A", title: "N/A", users: unlistedVisible))
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
        guard !filter.isEmpty || !queryTokens.isEmpty else {
            // The N/A rows are not directory members, so they are counted
            // apart rather than folded into the users figure.
            subtitle = unlistedVisible.isEmpty
                ? base
                : base + " · \(unlistedVisible.count) not in directory"
            return
        }
        let total = Self.decimal.string(from: NSNumber(value: all.count)) ?? "\(all.count)"
        subtitle = "\(base) · filtered from \(total)"
    }

    /// Re-applies the filter and the search box, and everything derived from
    /// them. The search narrows the same list the filter does; the two stack.
    private func rebuildAll() {
        queryTokens = SerbianLatin.fold(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if filter.isEmpty && queryTokens.isEmpty {
            visible = all
        } else if queryTokens.isEmpty {
            visible = all.filter(filter.matches)
        } else if filter.isEmpty {
            visible = all.filter(matchesQuery)
        } else {
            visible = all.filter { filter.matches($0) && matchesQuery($0) }
        }
        // The 83 have no city, company or join year, so every filter excludes
        // them -- but they do have a username, which the search can match.
        unlistedVisible = queryTokens.isEmpty ? unlisted : unlisted.filter(matchesQuery)

        rebuildSubtitle()
        rebuildSections()
    }

    var body: some View {
        NavigationStack(path: $router.path) {
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
            .archiveDestinations(router)
            // Same placement rule as the Search tab: the phone's default is
            // already a full-width field under the title, an iPad's is a
            // cramped one in the toolbar.
            .searchable(text: $query,
                        placement: Device.isPad
                            ? .navigationBarDrawer(displayMode: .always) : .automatic,
                        prompt: "Search name, city or company")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
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
                } else if visible.isEmpty && unlistedVisible.isEmpty {
                    // With a search running, the standard "no results for …"
                    // is the right message: offering "Clear Filters" for a
                    // typo in the search box would clear the wrong thing.
                    if !queryTokens.isEmpty, filter.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentUnavailableView {
                            Label("No matching users",
                                  systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text(queryTokens.isEmpty
                                 ? "No one in the archive matches every filter."
                                 : "No one matches both the filter and the search.")
                        } actions: {
                            Button("Clear Filters") { filter = UserFilter() }
                        }
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
                // Reading 8,105 rows and folding them is not main-thread work:
                // done inline it held the tab on the previous screen until it
                // finished, which is what made the first tap feel slow.
                let loadedData = await Task.detached(priority: .userInitiated) {
                    let people = (try? UsersRepository.allUsers()) ?? []
                    // 83 rows, so loading them with the directory costs nothing.
                    let absent = ((try? UsersRepository.unlistedAuthors()) ?? [])
                        .map { (SerbianLatin.key($0.username), $0) }
                        .sorted { $0.0 < $1.0 }
                        .map(\.1)
                    // One fold per person rather than one per keystroke. Both
                    // the directory and the 83 unlisted authors go in, so a
                    // search can reach either.
                    var hay: [Int64: String] = [:]
                    var keys: [Int64: String] = [:]
                    hay.reserveCapacity(people.count + absent.count)
                    keys.reserveCapacity(people.count + absent.count)
                    for u in people + absent {
                        hay[u.id] = SerbianLatin.fold(
                            [u.username, u.fullName ?? "", u.city ?? "", u.company ?? ""]
                                .joined(separator: " "))
                        keys[u.id] = SerbianLatin.key(u.username)
                    }
                    return (people, absent, hay, keys)
                }.value
                (all, unlisted, haystack, nameKeys) = loadedData
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
            .onChange(of: query) { _, _ in if loaded { rebuildAll() } }
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
                if sort.indexesByYear, let v = ArchiveDate.day(sort.value(user)) {
                    Text(v).font(.caption2).foregroundStyle(.secondary)
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
