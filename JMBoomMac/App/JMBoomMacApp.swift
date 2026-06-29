import SwiftUI

@main
struct JMBoomMacApp: App {
    @State private var settings = AppSettings()
    @State private var router = AppRouter()
    @State private var history = ReadingHistoryStore()
    @State private var favorites = FavoriteStore()
    @State private var downloads = DownloadStore()
    @State private var purchases = PurchasedComicStore()
    @State private var userSession = UserSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(router)
                .environment(history)
                .environment(favorites)
                .environment(downloads)
                .environment(purchases)
                .environment(userSession)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
        }
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
