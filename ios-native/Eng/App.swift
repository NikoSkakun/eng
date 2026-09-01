import SwiftUI

@main
struct EngApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(app)
        }
    }
}
