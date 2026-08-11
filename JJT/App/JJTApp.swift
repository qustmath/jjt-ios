import SwiftUI

@main
struct JJTApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        }
    }
}
