import SwiftUI

@main
struct KegplayApp: App {
    @StateObject private var backend = Backend()

    var body: some Scene {
        WindowGroup("kegPlay") {
            ContentView().environmentObject(backend)
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }   // 1 cửa sổ là đủ
    }
}
