import AppKit
import SwiftUI

/// The menu bar item: left click plays or pauses, right click (or ⌃-click) opens the controls.
@MainActor
final class StatusItemController: NSObject {
    private let store: Store
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var countdown: Timer?

    init(store: Store) {
        self.store = store
        super.init()
        SettingsWindow.store = store

        let host = NSHostingController(rootView: ContentView().environment(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.toolTip = "Click to play or pause · Right-click for controls"
        }
        refresh()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu || popover.isShown {
            togglePopover()
        } else {
            store.togglePlay()
        }
    }

    private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Redraws the button, then re-arms itself on the next change to anything it read.
    private func refresh() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        let needsCountdown = store.timer != nil && store.showTimerInMenuBar
        if needsCountdown, countdown == nil {
            countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateButton() }
            }
        } else if !needsCountdown {
            countdown?.invalidate()
            countdown = nil
        }
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let symbol = store.isAudible ? "cloud.rain.fill" : "cloud.rain"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Serenity")
        image?.isTemplate = true
        button.image = image
        if let timer = store.timer, store.showTimerInMenuBar {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = NSAttributedString(string: " " + formatShort(timer.remaining),
                                                        attributes: [.font: font])
        } else {
            button.title = ""
        }
    }
}

/// The Settings window, created on first use.
@MainActor
enum SettingsWindow {
    static var store: Store?
    private static var window: NSWindow?

    static func show() {
        if window == nil, let store {
            let host = NSHostingController(rootView: SettingsView().environment(store))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = "Serenity Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
