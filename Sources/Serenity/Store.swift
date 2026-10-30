import Foundation
import MediaPlayer
import Observation
import ServiceManagement

struct Mix: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var volumes: [String: Double]
    var created: Date
}

enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case stop, start, fade
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stop: return "Stop after"
        case .start: return "Start after"
        case .fade: return "Fade"
        }
    }
}

struct ActiveTimer {
    var mode: TimerMode
    var start: Date
    var end: Date
    var message: String
    var from: [String: Double] = [:]
    var to: [String: Double] = [:]
    /// Volumes restored after a fade to silence, so pressing play brings the mix back.
    var restore: [String: Double]?

    var remaining: TimeInterval { max(0, end.timeIntervalSinceNow) }
}

private struct Persisted: Codable {
    var volumes: [String: Double]
    var globalVolume: Double
    var visible: [String]
    var mixes: [Mix]
    var meander: Bool
    var timerMode: TimerMode
    var timerHours: Int
    var timerMinutes: Int
    var showTimerInMenuBar: Bool?
    var hotkeys: [HotkeyAction: Hotkey]?
    var order: [String]?
}

@MainActor
@Observable
final class Store {
    static let threshold = 0.02

    var volumes: [String: Double] = [:] { didSet { changed() } }
    var globalVolume: Double = 0.8 { didSet { changed() } }
    var isPlaying = false { didSet { changed(); updateNowPlaying() } }
    var meander = false { didSet { resetMeander(); changed() } }
    var visible: Set<String> = [] { didSet { scheduleSave() } }
    /// User-chosen order of sounds; always contains every catalog key exactly once.
    var order: [String] = Catalog.all.map(\.key) { didSet { scheduleSave() } }
    var mixes: [Mix] = [] { didSet { scheduleSave() } }

    // Timer form
    var timerMode: TimerMode = .stop { didSet { scheduleSave() } }
    var timerHours = 0 { didSet { scheduleSave() } }
    var timerMinutes = 30 { didSet { scheduleSave() } }
    var fadeOrigin = "current"
    var fadeDestination = "silence"
    var showTimerInMenuBar = true { didSet { scheduleSave() } }

    private(set) var timer: ActiveTimer? { didSet { updateTicker() } }

    var hotkeys: [HotkeyAction: Hotkey] = [:] { didSet { registerHotkeys(); scheduleSave() } }
    /// Hotkeys are suspended while one is being recorded, so the current combo can be re-captured.
    var recordingHotkey = false { didSet { registerHotkeys() } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Serenity: launch at login failed: \(error)")
            }
        }
    }

    // Meander state (mirrors asoftmurmur's algorithm, but with sub-second ticks for smoothness)
    @ObservationIgnored private var meanderClock: Double = 0
    @ObservationIgnored private var meanderOffsets: [String: Double] = [:]
    @ObservationIgnored private var meanderCycle: [String: Int] = [:]
    @ObservationIgnored private var meanderUp: [String: Bool] = [:]
    private(set) var effective: [String: Double] = [:]

    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var loading = true
    private static let tickInterval = 0.1

    init() {
        load()
        loading = false
        setupRemoteCommands()
        registerHotkeys()
        apply()
    }

    var orderedSounds: [SoundInfo] { order.compactMap { Catalog.byKey[$0] } }
    var visibleSounds: [SoundInfo] { orderedSounds.filter { visible.contains($0.key) } }
    var activeSounds: [SoundInfo] { orderedSounds.filter { volume($0.key) > Self.threshold } }
    var isAudible: Bool { isPlaying && !activeSounds.isEmpty }

    func volume(_ key: String) -> Double { volumes[key] ?? 0 }

    func setVolume(_ key: String, _ value: Double) {
        volumes[key] = value <= Self.threshold ? 0 : value
        meanderOffsets[key] = meanderClock
        meanderCycle[key] = nil
    }

    /// Tapping a sound's icon steps through 34% → 64% → 100% → off, like the website.
    func cycle(_ key: String) {
        let v = volume(key)
        setVolume(key, v < 0.3 ? 0.34 : v < 0.6 ? 0.64 : v < 0.98 ? 1 : 0)
        if volume(key) > 0 && !isPlaying { isPlaying = true }
    }

    func togglePlay() { isPlaying.toggle() }

    func setVisible(_ key: String, _ on: Bool) {
        if on { visible.insert(key) } else { visible.remove(key); if volume(key) > 0 { setVolume(key, 0) } }
    }

    func moveSounds(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    func showAllSounds() { visible = Set(order) }

    func hideAllSounds() {
        visible = []
        volumes = [:]
    }

    func resetSoundList() {
        order = Catalog.all.map(\.key)
        visible = Set(Catalog.all.filter(\.defaultVisible).map(\.key))
        volumes = volumes.filter { visible.contains($0.key) }
    }

    // MARK: Mixes

    func saveMix(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let active = volumes.filter { $0.value > Self.threshold }
        guard !active.isEmpty else { return }
        let mix = Mix(id: UUID().uuidString, name: trimmed.isEmpty ? MixNamer.name(for: Array(active.keys)) : trimmed,
                      volumes: active, created: Date())
        mixes.append(mix)
    }

    func load(_ mix: Mix) {
        apply(volumes: mix.volumes)
    }

    func delete(_ mix: Mix) {
        mixes.removeAll { $0.id == mix.id }
    }

    var sortedMixes: [Mix] { mixes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    /// Picks 2–3 random sounds whose volumes add up to 100%, like the site's "random mix". Returns a name for it.
    @discardableResult
    func randomMix() -> String {
        var pool = Catalog.all.map(\.key)
        let count = [2, 3].randomElement()!
        var remaining = 100
        var result: [String: Double] = [:]
        for i in 0..<count {
            var idx = Int.random(in: 0..<pool.count)
            if Catalog.noise.contains(pool[idx]) { idx = Int.random(in: 0..<pool.count) }
            let share = i + 1 == count ? remaining : Int.random(in: 10...max(10, remaining - 10 * (count - i - 1)))
            remaining -= share
            result[pool[idx]] = Double(share) / 100
            pool.remove(at: idx)
        }
        apply(volumes: result)
        return MixNamer.name(for: Array(result.keys))
    }

    private func apply(volumes newVolumes: [String: Double]) {
        newVolumes.keys.forEach { visible.insert($0) }
        meanderOffsets = [:]
        meanderCycle = [:]
        volumes = newVolumes
        isPlaying = true
    }

    // MARK: Timer

    func fadeOptions() -> [(tag: String, label: String)] {
        [("current", "Current volume"), ("silence", "Silence")] +
            sortedMixes.map { ("mix:\($0.id)", String($0.name.prefix(32))) }
    }

    func setFadeOrigin(_ tag: String) {
        fadeOrigin = tag
        if fadeDestination == tag { fadeDestination = tag == "silence" ? "current" : "silence" }
    }

    func setFadeDestination(_ tag: String) {
        fadeDestination = tag
        if fadeOrigin == tag { fadeOrigin = tag == "current" ? "silence" : "current" }
    }

    func startTimer(seconds overrideSeconds: Int? = nil) {
        let seconds = overrideSeconds ?? (timerHours * 3600 + timerMinutes * 60)
        guard seconds > 0 else { return }
        let now = Date()
        var t = ActiveTimer(mode: timerMode, start: now, end: now.addingTimeInterval(TimeInterval(seconds)), message: "")
        switch timerMode {
        case .stop:
            t.message = "Sounds will stop in"
            isPlaying = true
        case .start:
            t.message = "Sounds will start in"
            isPlaying = false
        case .fade:
            let current = volumes
            t.from = volumes(for: fadeOrigin, current: current)
            t.to = volumes(for: fadeDestination, current: current)
            switch fadeDestination {
            case "current": t.message = "Fade in will finish in"
            case "silence":
                t.message = "Fade out will finish in"
                t.restore = fadeOrigin == "current" ? current : t.from
            default: t.message = "Fade to \u{201C}\(mixName(fadeDestination))\u{201D} will finish in"
            }
            (Array(t.from.keys) + Array(t.to.keys)).filter { (t.from[$0] ?? 0) > 0 || (t.to[$0] ?? 0) > 0 }
                .forEach { visible.insert($0) }
            volumes = t.from
            isPlaying = true
        }
        timer = t
    }

    func cancelTimer() { timer = nil }

    private func mixName(_ tag: String) -> String {
        mixes.first { "mix:\($0.id)" == tag }?.name ?? "mix"
    }

    private func volumes(for tag: String, current: [String: Double]) -> [String: Double] {
        switch tag {
        case "current": return current
        case "silence": return [:]
        default: return mixes.first { "mix:\($0.id)" == tag }?.volumes ?? [:]
        }
    }

    // MARK: Tick (timer + meander)

    private func updateTicker() {
        let needed = timer != nil || (meander && isPlaying)
        if needed, ticker == nil {
            let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.02
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !needed, let t = ticker {
            t.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        if let t = timer {
            if t.mode == .fade {
                let total = t.end.timeIntervalSince(t.start)
                let p = min(1, max(0, 1 - t.remaining / total))
                var v: [String: Double] = [:]
                for key in Set(t.from.keys).union(t.to.keys) {
                    let x = (t.from[key] ?? 0) + ((t.to[key] ?? 0) - (t.from[key] ?? 0)) * p
                    if x > 0.001 { v[key] = x }
                }
                volumes = v
            }
            if t.remaining <= 0 {
                timer = nil
                switch t.mode {
                case .stop: isPlaying = false
                case .start: isPlaying = true
                case .fade:
                    if let restore = t.restore {
                        isPlaying = false
                        volumes = restore
                    } else {
                        volumes = t.to
                    }
                }
            }
        }
        if meander && isPlaying {
            meanderClock += Self.tickInterval
            apply()
        }
    }

    private func resetMeander() {
        meanderClock = 0
        meanderOffsets = [:]
        meanderCycle = [:]
        updateTicker()
    }

    private func meanderVolume(_ key: String, base: Double) -> Double {
        guard meander, base > Self.threshold else { return base }
        let elapsed = meanderClock - (meanderOffsets[key] ?? 0)
        let cycle = Int(elapsed / 60)
        if meanderCycle[key] != cycle {
            meanderCycle[key] = cycle
            meanderUp[key] = Bool.random()
        }
        let up = meanderUp[key] ?? true
        let a = elapsed.truncatingRemainder(dividingBy: 60)
        let target = up ? base + (1 - base) / 3 : base / 1.5
        let delta = (a > 30 ? 60 - a : a) * abs(base - target) / 30
        return up ? base + delta : base - delta
    }

    // MARK: Audio + persistence

    private func changed() {
        guard !loading else { return }
        updateTicker()
        apply()
        scheduleSave()
    }

    private func apply() {
        audio.masterVolume = Float(globalVolume)
        var eff: [String: Double] = [:]
        for s in Catalog.all {
            let base = volume(s.key)
            let v = meanderVolume(s.key, base: base)
            if base > Self.threshold { eff[s.key] = v }
            audio.set(s.key, volume: Float(v), playing: isPlaying && base > Self.threshold)
        }
        effective = eff
    }

    private static let defaultsKey = "state.v1"

    private func load() {
        // One-time import of settings from when the app was called Murmur.
        if UserDefaults.standard.data(forKey: Self.defaultsKey) == nil,
           let old = UserDefaults(suiteName: "local.murmur.app")?.data(forKey: Self.defaultsKey) {
            UserDefaults.standard.set(old, forKey: Self.defaultsKey)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else {
            visible = Set(Catalog.all.filter(\.defaultVisible).map(\.key))
            volumes = ["rain": 0.5]
            return
        }
        volumes = p.volumes
        globalVolume = p.globalVolume
        visible = Set(p.visible)
        mixes = p.mixes
        meander = p.meander
        timerMode = p.timerMode
        timerHours = p.timerHours
        timerMinutes = p.timerMinutes
        showTimerInMenuBar = p.showTimerInMenuBar ?? true
        hotkeys = p.hotkeys ?? [:]
        let saved = (p.order ?? []).filter { Catalog.byKey[$0] != nil }
        order = saved + Catalog.all.map(\.key).filter { !saved.contains($0) }
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func save() {
        // While fading, persist the pre-fade mix rather than an intermediate level.
        let vols = timer?.mode == .fade ? (timer?.restore ?? timer?.to ?? volumes) : volumes
        let p = Persisted(volumes: vols, globalVolume: globalVolume, visible: Array(visible), mixes: mixes,
                          meander: meander, timerMode: timerMode, timerHours: timerHours,
                          timerMinutes: timerMinutes, showTimerInMenuBar: showTimerInMenuBar,
                          hotkeys: hotkeys, order: order)
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: Hotkeys

    private func registerHotkeys() {
        guard !loading else { return }
        let bindings: [(Hotkey, () -> Void)] = recordingHotkey ? [] : hotkeys.map { action, hotkey in
            (hotkey, { [weak self] in
                guard let self else { return }
                switch action {
                case .toggle: self.togglePlay()
                case .play: self.isPlaying = true
                case .stop: self.isPlaying = false
                }
            })
        }
        HotkeyCenter.shared.register(bindings)
    }

    // MARK: Media keys / Now Playing

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = true }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
            return .success
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard !loading else { return }
        let names = activeSounds.map(\.label).joined(separator: ", ")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: names.isEmpty ? "Serenity" : names,
            MPMediaItemPropertyArtist: "Serenity",
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
