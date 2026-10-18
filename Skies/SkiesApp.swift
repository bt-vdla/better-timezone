import SwiftUI

@main
struct SkiesApp: App {
    var body: some Scene {
        WindowGroup {
            SkiesView()
                #if os(macOS)
                .frame(minWidth: 340, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 390, height: 800)
        .windowResizability(.contentMinSize)
        #endif
    }
}
