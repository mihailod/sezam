import SwiftUI

enum Tab: Hashable { case users, conferences, search, settings }

/// The push path for one tab's stack.
///
/// A deep view sometimes has to push without being a `NavigationLink`: a link
/// inside a list row hands the whole row to it, which made a tap anywhere in a
/// message open its author. Appending here pushes exactly the same way while
/// leaving the rest of the row inert.
///
/// The alternative, `navigationDestination(item:)` next to the tap, is worse
/// than it looks: the binding stays set after the push, so the next push
/// re-presents the same view on top of it -- tapping a message on an author's
/// page showed that author again, with the thread stranded underneath.
@MainActor
@Observable
final class NavRouter {
    var path = NavigationPath()
}

/// Every push in the app, declared once at the root of each stack.
///
/// SwiftUI resolves `navigationDestination` per stack, and declaring a type
/// twice in one stack is undefined: it logs "declared earlier on the stack" and
/// keeps only the declaration nearest the root. That is exactly what happened
/// once a reader drilled thread → author → profile → message → thread, because
/// the second thread re-declared the author destination. Taps then resolved
/// against the first thread's copy, so some opened the wrong page and Back
/// could land on an empty screen.
///
/// Keeping them here means every stack pushes the same way, and no pushed view
/// ever declares a destination of its own.
extension View {
    func archiveDestinations(_ router: NavRouter) -> some View {
        self
            .navigationDestination(for: UserItem.self) { UserMessagesView(user: $0) }
            .navigationDestination(for: AuthorLink.self) { AuthorProfileView(username: $0.username) }
            .navigationDestination(for: ThreadTarget.self) {
                MessageListView(topic: $0.topic, anchor: $0.anchor, router: router)
            }
            .navigationDestination(for: ConferenceFamily.self) { TopicListView(family: $0) }
    }
}

struct RootView: View {
    @State private var tab: Tab = .conferences
    @State private var bootstrap = AppBootstrap()
    @State private var settings = AppSettings.shared
    /// Read before this view applies its own override, so this is the real
    /// system setting — the fallback when the user has not chosen one.
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    var body: some View {
        Group {
            switch bootstrap.state {
            case .checking:
                ProgressView().controlSize(.large)
            case let .needsInstall(reason):
                DownloadView(bootstrap: bootstrap, reason: reason)
            case .ready:
                tabs
            }
        }
        .environment(bootstrap)
        // One override at the root scales every semantic font in the app.
        // With no override stored this re-applies the system value, which is a
        // no-op — so the app follows iOS until the user says otherwise.
        .environment(\.dynamicTypeSize, settings.overrideSize ?? systemTypeSize)
        .environment(\.systemTypeSize, systemTypeSize)
        .task { bootstrap.check() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            UsersView()
                .tabItem { Label("Users", systemImage: "person.2") }
                .tag(Tab.users)

            BrowseView()
                .tabItem { Label("Conferences", systemImage: "square.stack.3d.up") }
                .tag(Tab.conferences)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview { RootView() }
