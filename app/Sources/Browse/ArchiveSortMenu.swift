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

/// The sort menu the conference list and the topic list share, so the two
/// cannot drift apart.
///
/// Matches the one on the Users tab: Buttons rather than a Picker, because a
/// Section around a Picker does not render its header here, with or without
/// .inline, so the checkmark is drawn by hand.
struct ArchiveSortMenu: View {
    @Binding var sort: ArchiveSort

    var body: some View {
        Menu {
            Section("Sort by:") {
                ForEach(ArchiveSort.allCases) { option in
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
