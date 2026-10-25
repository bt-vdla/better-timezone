import SwiftUI

@main
struct SkiesApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacDelegate.self) private var delegate
    @AppStorage("hotkey.label") private var hotkey = "⌃⌥S"
    #endif

    var body: some Scene {
        #if os(macOS)
        // Notch-first: no Dock icon. The notch opens with the hotkey; the full window opens from here or the notch.
        MenuBarExtra("Skies", systemImage: "sun.horizon.fill") {
            Button("Show in Notch  \(hotkey)") { NotchController.shared.open() }
            Button("Open Skies") { MainWindow.shared.show() }
            Divider()
            SettingsLink { Text("Settings…") }.keyboardShortcut(",")
            Button("Quit Skies") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SkiesSettings() }
        #else
        WindowGroup { RootView() }
        #endif
    }
}

struct RootView: View {
    @State private var people = People.shared
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
        // Widgets open skies://person/<id> to land on that person's page.
        .onOpenURL { url in
            if url.host == "person", let id = UUID(uuidString: url.lastPathComponent) { people.focus = id }
        }
    }
}
