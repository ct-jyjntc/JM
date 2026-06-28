import SwiftUI

@main
struct JMBoomMacApp: App {
    @State private var settings = AppSettings()
    @State private var router = AppRouter()
    @State private var history = ReadingHistoryStore()
    @State private var favorites = FavoriteStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(router)
                .environment(history)
                .environment(favorites)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
        }
    }
}
