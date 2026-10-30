import AppKit
import SwiftUI

@main
struct SerenityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
                .onAppear { delegate.store = store }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Serenity Settings", id: "settings") {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: Store?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { store?.save() }
    }
}

struct MenuBarLabel: View {
    let store: Store

    var body: some View {
        if let timer = store.timer, store.showTimerInMenuBar {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 4) {
                    Image(systemName: store.isAudible ? "cloud.rain.fill" : "cloud.rain")
                    Text(formatShort(timer.remaining)).monospacedDigit()
                }
            }
        } else {
            Image(systemName: store.isAudible ? "cloud.rain.fill" : "cloud.rain")
        }
    }
}

func formatShort(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
