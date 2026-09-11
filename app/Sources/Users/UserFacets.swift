import Foundation

/// One selectable value in the filter sheet: a folded key, the spelling shown
/// to the reader, and how many users carry it.
struct Facet: Identifiable, Hashable {
    let id: String          // folded key -- what the filter stores
    let label: String       // canonical raw spelling -- what is displayed
    let count: Int
}

/// Groups free-text profile fields into filterable values.
///
/// City and company were typed by hand over ten years, so the same place
/// arrives in several spellings: Beograd / Beograđ / beograd, Niš / Nis,
/// Računari / Racunari. Grouping by `SearchQuery.fold` (the same fold the
/// search index uses) collapses 656 cities to 628 and 1,521 companies to 1,505.
/// `UserAliases` then merges the hand-approved cases folding cannot reach,
/// taking company down to 1,438.
///
/// All of this is for finding people. The values shown on a user row are
/// untouched -- see `display`.
///
/// This runs in the app rather than the database on purpose: the 333 MB archive
/// is already published, and a schema change would force every reader to
/// download it again for a grouping the reader never sees stored.
enum UserFacets {
    /// Blank and missing values share one bucket. The empty string cannot
    /// collide with a real folded value, so it doubles as the "Not Specified"
    /// key and needs no separate flag on the filter.
    static let unspecified = ""

    /// City and company are keyed separately. They share a namespace of folded
    /// strings -- the city Niš and a company called NIS would both key as
    /// "nis" -- so one shared table would let a company's label leak onto a
    /// city row, and a company merge would silently apply to cities.
    static func key(_ raw: String?, _ field: FilterSection) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespaces)
        // "/", "-" and "------" were typed to mean "none". They carry no more
        // information than a blank field, so they join Not Specified instead of
        // standing as their own one-user entries.
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else {
            return unspecified
        }
        let folded = SearchQuery.fold(trimmed).lowercased()
        return UserAliases.keyMap(for: field)[folded] ?? folded
    }

    /// A member's company key. Normally the company name alone. For the few
    /// names unrelated firms shared (`UserAliases.companiesSplitByCity`), the
    /// member's city becomes part of the key, so each firm gets its own entry:
    /// "Infotrade Priština" and "Infotrade Sremčica" rather than one Infotrade
    /// spanning both. Two members who typed the identical name cannot be told
    /// apart any other way.
    static func companyKey(_ u: UserItem) -> String {
        let k = key(u.company, .company)
        guard k != unspecified, UserAliases.companySplitKeys.contains(k) else { return k }
        return k + String(splitSeparator) + key(u.city, .city)
    }

    /// Joins a split company key to its city key. A control character, so it
    /// can never occur inside a folded name.
    private static let splitSeparator: Character = "\u{1F}"

    /// What a user row shows: exactly what the member typed, minus the values
    /// that mean "nothing".
    ///
    /// Deliberately *not* the merged or canonical spelling. Grouping is a
    /// search convenience -- ticking `PTT` should reach the person at
    /// `Ptt Vukovar` -- but their profile said Vukovar and the row still says
    /// Vukovar. Rewriting displayed values would quietly edit a historical
    /// record to make a filter tidier.
    static func display(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return trimmed
    }

    /// Facets ordered by user count, most common first, with "Not Specified"
    /// pinned last regardless of size -- for company it is 6,488 of 8,105 users
    /// and would otherwise bury every real employer.
    static func build(_ users: [UserItem], field: FilterSection) -> [Facet] {
        let value: (UserItem) -> String? = field == .city ? { $0.city } : { $0.company }
        let preferred = UserAliases.labelMap(for: field)

        // Keyed per member rather than per name, so a shared company name can
        // be split by the member's city.
        let keyOf: (UserItem) -> String =
            field == .company ? { companyKey($0) } : { key($0.city, .city) }
        var spellings: [String: [String: Int]] = [:]
        var splitCities: [String: [String: Int]] = [:]
        var totals: [String: Int] = [:]
        for u in users {
            let k = keyOf(u)
            totals[k, default: 0] += 1
            if k != unspecified {
                let raw = (value(u) ?? "").trimmingCharacters(in: .whitespaces)
                spellings[k, default: [:]][raw, default: 0] += 1
                if k.contains(splitSeparator) {
                    let city = (u.city ?? "").trimmingCharacters(in: .whitespaces)
                    splitCities[k, default: [:]][city, default: 0] += 1
                }
            }
        }

        var facets: [Facet] = []
        facets.reserveCapacity(totals.count)
        for (k, total) in totals where k != unspecified {
            // An approved merge names the spelling to keep. Otherwise take the
            // most frequent one, which in practice is the correctly accented
            // form: Niš (156) outvotes Nis (3), Pančevo (68) outvotes Pancevo
            // (6). Ties break on the spelling itself so the label never depends
            // on dictionary ordering and stays stable between launches.
            let parts = k.split(separator: splitSeparator, omittingEmptySubsequences: false)
            let base = parts.first.map(String.init) ?? k
            var label = preferred[base] ?? spellings[k]?
                .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? k
            if parts.count == 2 {
                // A split entry is "<company> <city>", with the city spelled
                // the way the city filter spells it.
                let city = UserAliases.labelMap(for: .city)[String(parts[1])]
                    ?? splitCities[k]?.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
                    ?? ""
                if !city.isEmpty { label += " " + city }
            }
            facets.append(Facet(id: k, label: label, count: total))
        }

        facets.sort { ($1.count, SerbianLatin.key($0.label))
                    < ($0.count, SerbianLatin.key($1.label)) }

        if let blank = totals[unspecified], blank > 0 {
            facets.append(Facet(id: unspecified, label: "[Not specified]", count: blank))
        }
        return facets
    }

    /// A city nobody could place. It gets its own row rather than joining Not
    /// Specified: those members did type something, it just cannot be resolved.
    static let ambiguous = "[Ambiguous]"

    /// The region a member's city is in. Keyed through the city facet, so an
    /// approved merge -- Beograd (Borča) into Beograd -- carries over here.
    static func region(_ u: UserItem) -> String {
        let city = key(u.city, .city)
        if city == unspecified { return unspecified }
        return UserAliases.regionByCity[city] ?? ambiguous
    }

    /// Regions by user count, with Ambiguous and then Not Specified pinned
    /// last: both are answers about the data rather than places to filter by.
    static func buildRegions(_ users: [UserItem]) -> [Facet] {
        var totals: [String: Int] = [:]
        for u in users { totals[region(u), default: 0] += 1 }
        var facets = totals
            .filter { $0.key != unspecified && $0.key != ambiguous }
            .map { Facet(id: $0.key, label: $0.key, count: $0.value) }
        facets.sort { ($1.count, SerbianLatin.key($0.label))
                    < ($0.count, SerbianLatin.key($1.label)) }
        if let n = totals[ambiguous], n > 0 {
            facets.append(Facet(id: ambiguous, label: ambiguous, count: n))
        }
        if let n = totals[unspecified], n > 0 {
            facets.append(Facet(id: unspecified, label: "[Not specified]", count: n))
        }
        return facets
    }

    /// Join years, oldest first. Every user in the archive has one and they all
    /// fall inside 1989-1999, so this needs no "Not Specified" bucket -- but it
    /// is derived from the data rather than hard-coded, so a later harvest that
    /// does carry gaps still renders correctly.
    static func years(_ users: [UserItem]) -> [Facet] {
        var totals: [String: Int] = [:]
        for u in users { totals[UserItem.year(u.joinedISO) ?? unspecified, default: 0] += 1 }
        var facets = totals.filter { $0.key != unspecified }
            .map { Facet(id: $0.key, label: $0.key, count: $0.value) }
            .sorted { $0.id < $1.id }
        if let blank = totals[unspecified], blank > 0 {
            facets.append(Facet(id: unspecified, label: "[Not specified]", count: blank))
        }
        return facets
    }
}

/// Checked values, by section. Empty means "no restriction from this section".
///
/// Within a section the checks are OR'd and across sections they are AND'd:
/// Beograd + Novi Sad + 1995 reads as "from either city, joined in 1995".
/// OR-ing across sections instead would return everyone in Beograd *plus*
/// everyone who joined in 1995, which is always a larger set than either check
/// alone and so is never what a filter is for.
struct UserFilter: Equatable {
    var cities: Set<String> = []
    var companies: Set<String> = []
    var years: Set<String> = []
    var regions: Set<String> = []

    var isEmpty: Bool {
        cities.isEmpty && companies.isEmpty && years.isEmpty && regions.isEmpty
    }
    var count: Int {
        cities.count + companies.count + years.count + regions.count
    }

    func matches(_ u: UserItem) -> Bool {
        if !cities.isEmpty, !cities.contains(UserFacets.key(u.city, .city)) { return false }
        if !companies.isEmpty,
           !companies.contains(UserFacets.companyKey(u)) { return false }
        if !years.isEmpty,
           !years.contains(UserItem.year(u.joinedISO) ?? UserFacets.unspecified) { return false }
        if !regions.isEmpty, !regions.contains(UserFacets.region(u)) { return false }
        return true
    }

    mutating func toggle(_ id: String, in section: FilterSection) {
        switch section {
        case .city:    toggle(id, &cities)
        case .company: toggle(id, &companies)
        case .year:    toggle(id, &years)
        case .region:  toggle(id, &regions)
        }
    }

    func contains(_ id: String, in section: FilterSection) -> Bool {
        switch section {
        case .city:    return cities.contains(id)
        case .company: return companies.contains(id)
        case .year:    return years.contains(id)
        case .region:  return regions.contains(id)
        }
    }

    /// How many values are ticked in one section, for its header.
    func count(in section: FilterSection) -> Int {
        switch section {
        case .city:    return cities.count
        case .company: return companies.count
        case .year:    return years.count
        case .region:  return regions.count
        }
    }

    private func toggle(_ id: String, _ set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

enum FilterSection { case city, company, year, region }
