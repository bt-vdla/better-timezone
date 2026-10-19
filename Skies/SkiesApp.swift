import SwiftUI

@main
struct SkiesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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

struct RootView: View {
    @State private var people = People()
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            if onboarded {
                SkiesView(people: people).transition(.opacity)
            } else {
                Onboarding(people: people) { onboarded = true }.transition(.opacity)
            }
        }
        .animation(.easeOutStrong(0.4), value: onboarded)
    }
}
