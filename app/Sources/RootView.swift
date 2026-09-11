import SwiftUI

enum Tab: Hashable { case users, conferences, search, settings }

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
