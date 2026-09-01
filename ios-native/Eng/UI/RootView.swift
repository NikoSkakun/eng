import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            DictionaryView()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
