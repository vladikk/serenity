import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case sounds = "Sounds", timer = "Timer", mixes = "Mixes"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @AppStorage("tab") private var tab: Tab = .sounds

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch tab {
                case .sounds: SoundsView()
                case .timer: TimerView()
                case .mixes: MixesView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            Divider()
            FooterView()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

// MARK: Header

struct HeaderView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 12) {
            HStack {
                Button { store.meander.toggle() } label: {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(store.meander ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(store.meander ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Meander: the volume of each active sound wanders up and down at random.")

                Spacer()

                Button { store.togglePlay() } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(store.isPlaying ? "Pause (Space)" : "Play (Space)")

                Spacer()

                // Balances the meander button so play stays centered.
                Color.clear.frame(width: 34, height: 34)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                Slider(value: $store.globalVolume, in: 0...1)
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).font(.caption)
            }
            .help("Master volume")

            if let timer = store.timer {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        Image(systemName: "timer")
                        Text("\(timer.message) \(formatShort(timer.remaining))").monospacedDigit()
                        Spacer()
                        Button("Stop timer") { store.cancelTimer() }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Sounds

struct SoundsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.visibleSounds) { SoundRow(sound: $0) }
                if store.visibleSounds.isEmpty {
                    Text("No sounds shown. Choose some in Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: min(CGFloat(max(store.visibleSounds.count, 3)) * 40 + 16, 440))
    }
}

struct SoundRow: View {
    @Environment(Store.self) private var store
    let sound: SoundInfo

    var body: some View {
        let vol = store.volume(sound.key)
        let live = store.effective[sound.key] ?? vol
        HStack(spacing: 10) {
            Button { store.cycle(sound.key) } label: {
                ZStack {
                    Image(systemName: sound.symbol)
                        .foregroundStyle(.secondary.opacity(0.35))
                    Image(systemName: sound.symbol)
                        .foregroundStyle(Color.accentColor)
                        .opacity(live)
                }
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to cycle volume")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(sound.label).font(.callout)
                        .foregroundStyle(vol > 0 ? .primary : .secondary)
                    if store.meander && store.isPlaying && vol > 0 {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.system(size: 9)).foregroundStyle(Color.accentColor)
                    }
                }
                Slider(value: Binding(get: { vol }, set: { store.setVolume(sound.key, $0) }), in: 0...1)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 38)
    }
}

// MARK: Timer

struct TimerView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            if let timer = store.timer {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 8) {
                        Text(timer.message).foregroundStyle(.secondary)
                        Text(formatLong(timer.remaining))
                            .font(.system(size: 36, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Button("Stop timer") { store.cancelTimer() }
                            .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Picker("", selection: $store.timerMode) {
                    ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.timerMode == .fade {
                    Grid(alignment: .leading, verticalSpacing: 8) {
                        GridRow {
                            Text("Start point").foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { store.fadeOrigin }, set: { store.setFadeOrigin($0) })) {
                                ForEach(store.fadeOptions(), id: \.tag) { Text($0.label).tag($0.tag) }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("End point").foregroundStyle(.secondary)
                            Picker("", selection: Binding(get: { store.fadeDestination }, set: { store.setFadeDestination($0) })) {
                                ForEach(store.fadeOptions(), id: \.tag) { Text($0.label).tag($0.tag) }
                            }
                            .labelsHidden()
                        }
                    }
                    .font(.callout)
                }

                HStack(spacing: 6) {
                    TextField("", value: $store.timerHours, format: .number)
                        .frame(width: 40).multilineTextAlignment(.trailing)
                    Stepper("", value: $store.timerHours, in: 0...24).labelsHidden()
                    Text("hours")
                    Spacer().frame(width: 8)
                    TextField("", value: $store.timerMinutes, format: .number)
                        .frame(width: 40).multilineTextAlignment(.trailing)
                    Stepper("", value: $store.timerMinutes, in: 0...59).labelsHidden()
                    Text("minutes")
                }
                .font(.callout)

                HStack(spacing: 6) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                        Button(m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(m % 60)") {
                            store.timerHours = m / 60
                            store.timerMinutes = m % 60
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Spacer()
                    Button("Start timer") {
                        store.timerHours = min(max(store.timerHours, 0), 24)
                        store.timerMinutes = min(max(store.timerMinutes, 0), 59)
                        store.startTimer()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.timerHours * 60 + store.timerMinutes <= 0)
                }
            }
        }
        .padding(14)
    }

    private func formatLong(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

// MARK: Mixes

struct MixesView: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var pendingDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name this mix", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(store.activeSounds.isEmpty)
            }
            Button {
                name = store.randomMix()
            } label: {
                Label("Random mix", systemImage: "shuffle")
            }

            Divider()

            if store.mixes.isEmpty {
                Text("No saved mixes yet. Set up some sounds and save them here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.sortedMixes) { mix in mixRow(mix) }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(14)
    }

    private func save() {
        store.saveMix(named: name)
        name = ""
    }

    @ViewBuilder
    private func mixRow(_ mix: Mix) -> some View {
        HStack {
            Button { store.load(mix) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mix.name).font(.callout)
                    Text(mix.volumes.keys.compactMap { Catalog.byKey[$0] }.sorted { $0.sortKey < $1.sortKey }
                        .map(\.label).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Play this mix")

            if pendingDelete == mix.id {
                Button("Delete") { store.delete(mix); pendingDelete = nil }
                    .foregroundStyle(.red)
                Button("Cancel") { pendingDelete = nil }
            } else {
                Button { pendingDelete = mix.id } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Delete mix")
            }
        }
        .controlSize(.small)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }
}

// MARK: Footer

struct FooterView: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack {
            Text(store.isAudible ? store.activeSounds.map(\.label).joined(separator: " · ") : "Serenity")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Menu {
                Button("Settings…") { SettingsWindow.show() }
                .keyboardShortcut(",")
                Divider()
                Button("Quit Serenity") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: Settings

enum SettingsTab: String {
    case general, sounds, credits
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SoundSettings()
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.sounds)
            CreditsView()
                .tabItem { Label("Credits", systemImage: "heart") }
                .tag(SettingsTab.credits)
        }
        .frame(width: 440)
    }
}

struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) { HotkeyRecorder(action: action) }
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Work from any app. Click a field and press a key combination with ⌘, ⌥ or ⌃ (or a function key). Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        store.launchAtLogin = on
                        launchAtLogin = store.launchAtLogin
                    }
                Toggle("Show timer countdown in menu bar", isOn: $store.showTimerInMenuBar)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = store.launchAtLogin }
    }
}

struct SoundSettings: View {
    @Environment(Store.self) private var store
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0
    /// Set while a drag ends, so the mouse-up isn't also treated as a click.
    @State private var suppressTap = false
    private let rowHeight: CGFloat = 26

    var body: some View {
        let sounds = store.orderedSounds
        VStack(alignment: .leading, spacing: 8) {
            Text("Click a sound to show or hide it in the menu. Drag to reorder.")
                .font(.callout).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(sounds.enumerated()), id: \.element.key) { index, sound in
                    SoundChoiceRow(sound: sound, lifted: dragging == sound.key)
                        .frame(height: rowHeight)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                        .offset(y: offset(for: sound.key, at: index, count: sounds.count))
                        .zIndex(dragging == sound.key ? 1 : 0)
                        .animation(dragging == sound.key ? nil : .easeOut(duration: 0.15),
                                   value: targetIndex(count: sounds.count))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !suppressTap else { return }
                            store.setVisible(sound.key, !store.visible.contains(sound.key))
                        }
                        .gesture(dragGesture(for: sound.key, count: sounds.count))
                }
            }
            .coordinateSpace(name: "soundList")
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))

            HStack {
                Text("\(store.visible.count) of \(Catalog.all.count) shown")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show all") { store.showAllSounds() }
                Button("Hide all") { store.hideAllSounds() }
                Button("Reset") { store.resetSoundList() }
                    .help("Restore the default sounds and order")
            }
            .controlSize(.small)
        }
        .padding(20)
    }

    private var dragIndex: Int? { dragging.flatMap { store.order.firstIndex(of: $0) } }

    private func targetIndex(count: Int) -> Int? {
        guard let from = dragIndex else { return nil }
        return min(max(from + Int((dragOffset / rowHeight).rounded()), 0), count - 1)
    }

    /// The dragged row follows the pointer; rows it passes over slide out of the way.
    private func offset(for key: String, at index: Int, count: Int) -> CGFloat {
        if key == dragging { return dragOffset }
        guard let from = dragIndex, let to = targetIndex(count: count) else { return 0 }
        if from < to, index > from, index <= to { return -rowHeight }
        if to < from, index >= to, index < from { return rowHeight }
        return 0
    }

    private func dragGesture(for key: String, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("soundList"))
            .onChanged { value in
                if dragging == nil { dragging = key }
                suppressTap = true
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                if let from = dragIndex, let to = targetIndex(count: count), from != to {
                    store.moveSounds(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                }
                dragging = nil
                dragOffset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { suppressTap = false }
            }
    }
}

struct SoundChoiceRow: View {
    @Environment(Store.self) private var store
    let sound: SoundInfo
    let lifted: Bool

    var body: some View {
        let on = store.visible.contains(sound.key)
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(on ? Color.accentColor : .secondary)
            Image(systemName: sound.symbol)
                .frame(width: 22)
                .foregroundStyle(on ? Color.accentColor : .secondary)
            Text(sound.label)
                .foregroundStyle(on ? .primary : .secondary)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background {
            if lifted {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }
        }
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }
}

struct HotkeyRecorder: View {
    @Environment(Store.self) private var store
    let action: HotkeyAction
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Press shortcut…" : store.hotkeys[action]?.display ?? "Record shortcut")
                    .foregroundStyle(recording || store.hotkeys[action] == nil ? .secondary : .primary)
                    .frame(minWidth: 120)
            }
            if store.hotkeys[action] != nil && !recording {
                Button { store.hotkeys[action] = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        store.recordingHotkey = true
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if let hotkey = Hotkey(event: event) {
                // A combo can only drive one action.
                for (other, existing) in store.hotkeys where existing == hotkey { store.hotkeys[other] = nil }
                store.hotkeys[action] = hotkey
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { store.recordingHotkey = false }
        recording = false
    }
}

// MARK: Credits

struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sounds are built from freely licensed field recordings on Freesound.org. All recordings were modified: trimmed, joined with crossfades, made into seamless loops, loudness-normalised and re-encoded. Thank you to everyone who shared them.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(Catalog.all) { sound in
                    if let credit = Credits.all[sound.key] {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(sound.label, systemImage: sound.symbol).font(.headline)
                            if let generated = credit.generated {
                                Text(generated).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(credit.sources ?? [], id: \.url) { source in
                                HStack(spacing: 4) {
                                    Link("\u{201C}\(source.title)\u{201D} by \(source.author)", destination: source.url)
                                    Text("·").foregroundStyle(.secondary)
                                    Link(source.license, destination: source.licenseUrl)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(height: 560)
    }
}
