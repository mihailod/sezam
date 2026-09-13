import SwiftUI

/// The one sort order shared by the conference list and the topic list, so
/// picking "Last Active" on either puts both in that order.
///
/// Deliberately not persisted: the app should still open on First Post, which
/// is the order the archive reads in. This only outlives the screen, not the
/// launch.
@MainActor
@Observable
final class BrowseSortSelection {
    static let shared = BrowseSortSelection()
    private init() {}

    var value: ArchiveSort = .firstPost
}

extension ArchiveSort: SortOption {}
