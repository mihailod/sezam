import Foundation

struct UserItem: Identifiable, Hashable {
    let id: Int64
    let username: String
    let fullName: String?
    let city: String?
    let company: String?
    let joinedISO: String?
    let lastSeenISO: String?
    let messageCount: Int
    let authorID: Int64?
    /// False for the 83 people who posted but never appeared in the member
    /// directory. They carry a name and a message count and nothing else, so
    /// they sit in their own section and open a page that says as much.
    var isListed: Bool = true

    /// 7,918 of 7,975 names are exactly two tokens; the rest carry a middle
    /// name or initial ("Aleksandar P. Ranđić"), so last = final token holds.
    var firstName: String? {
        fullName?.split(separator: " ").first.map(String.init)
    }
    var lastName: String? {
        let parts = fullName?.split(separator: " ") ?? []
        return parts.count > 1 ? String(parts[parts.count - 1]) : nil
    }

    /// Exactly what the member typed, with "/" and "-" treated as blank.
    /// Merging and case folding belong to the filter, not to the record.
    var displayCity: String? { UserFacets.display(city) }
    var displayCompany: String? { UserFacets.display(company) }

    var subtitle: String {
        [displayCity, displayCompany]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func year(_ iso: String?) -> String? {
        guard let iso, iso.count >= 4 else { return nil }
        return String(iso.prefix(4))
    }
}

enum UserSort: String, CaseIterable, Identifiable {
    // Declaration order is menu order: `allCases` drives the Sort menu.
    case joined, messages, username, firstName, lastName, city, company, lastSeen
    var id: String { rawValue }

    var label: String {
        switch self {
        case .username:  return "Username"
        case .firstName: return "First Name"
        case .lastName:  return "Last Name"
        case .city:      return "City"
        case .company:   return "Company"
        case .joined:    return "Joined"
        case .lastSeen:  return "Last Seen"
        case .messages:  return "Messages Posted"
        }
    }

    /// Message count is numeric and ordered high-to-low, so it indexes by
    /// magnitude instead of letters or years.
    var indexesByMagnitude: Bool { self == .messages }

    /// Compact enough for the 20pt index strip; the section header spells it out.
    static let magnitudeBuckets: [(min: Int, id: String, title: String)] = [
        (1000, "1k+", "1,000+ messages"),
        (500,  "500", "500–999 messages"),
        (100,  "100", "100–499 messages"),
        (50,   "50",  "50–99 messages"),
        (10,   "10",  "10–49 messages"),
        (1,    "1",   "1–9 messages"),
        (0,    "0",   "never posted"),
    ]

    /// Joined / last seen index by year rather than letter.
    var indexesByYear: Bool { self == .joined || self == .lastSeen }

    func value(_ u: UserItem) -> String? {
        switch self {
        case .username:  return u.username
        case .firstName: return u.firstName
        case .lastName:  return u.lastName
        case .city:      return u.city
        case .company:   return u.company
        case .joined:    return u.joinedISO
        case .lastSeen:  return u.lastSeenISO
        case .messages:  return String(u.messageCount)
        }
    }

    /// Sort key, folded so Đ/Č sort with D/C instead of after Z.
    ///
    /// For message count the key is zero-padded and inverted, so the existing
    /// ascending string comparison yields highest-first — "9" would otherwise
    /// sort above "100".
    func sortKey(_ u: UserItem) -> String {
        if self == .messages {
            return String(format: "%09d", max(0, 999_999_999 - u.messageCount))
        }
        return SerbianLatin.key(displayValue(u) ?? "")
    }

    /// What the row actually shows. City and company are displayed in their
    /// canonical spelling, so sorting on the raw text would order rows by
    /// letters the reader cannot see.
    func displayValue(_ u: UserItem) -> String? {
        switch self {
        case .city:    return u.displayCity
        case .company: return u.displayCompany
        default:       return value(u)
        }
    }

    /// Section bucket: a year for date sorts, otherwise the folded first letter.
    /// 23 usernames begin with "." and one with a digit, so anything that is not
    /// A-Z lands in "#".
    func bucket(_ u: UserItem) -> String {
        if indexesByMagnitude {
            return Self.magnitudeBuckets.first { u.messageCount >= $0.min }?.id ?? "0"
        }
        if indexesByYear { return UserItem.year(value(u)) ?? "—" }
        return SerbianLatin.bucket(displayValue(u) ?? "")
    }

    /// Rows with no value at all sink to the bottom under "—". Zero messages is
    /// a real value, not a missing one, so it keeps its own bucket.
    func isMissing(_ u: UserItem) -> Bool {
        if self == .messages { return false }
        // City and company go through the facet key, so the values typed as
        // "/" or "-" count as missing here exactly as they do in the filter.
        if self == .city {
            return UserFacets.key(u.city, .city) == UserFacets.unspecified
        }
        if self == .company {
            return UserFacets.key(u.company, .company) == UserFacets.unspecified
        }
        return (value(u) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Section ordering. Alphabetical sorting of the bucket ids would place
    /// "100" before "1k+" and "10" before "500"; magnitude needs explicit ranks.
    func bucketRank(_ id: String) -> Int {
        if indexesByMagnitude {
            return Self.magnitudeBuckets.firstIndex { $0.id == id } ?? 99
        }
        if id == "#" { return -1 }
        if id == "—" { return 9_999 }
        // Č, Ć, Š and Ž are their own sections and must fall between C/D and
        // S/T and after Z. Ordering the bucket strings themselves would sort
        // every one of them after Z.
        return SerbianLatin.bucketOrder(id)
    }

    func bucketTitle(_ id: String) -> String {
        if indexesByMagnitude {
            return Self.magnitudeBuckets.first { $0.id == id }?.title ?? id
        }
        return id
    }
}

struct UserSection: Identifiable {
    let id: String          // bucket key: index-bar label and scroll target
    let title: String       // spelled out for the section header
    let users: [UserItem]
}
