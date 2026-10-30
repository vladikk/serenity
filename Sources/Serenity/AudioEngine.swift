import AVFoundation

/// Gapless looping playback of each sound via AVAudioEngine.
/// Files are streamed from disk; each player keeps one extra loop queued so there is no gap.
final class AudioEngine {
    private let engine = AVAudioEngine()
    private var players: [String: LoopPlayer] = [:]

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// Sets the volume of a sound and whether it should be audible right now.
    func set(_ key: String, volume: Float, playing: Bool) {
        if !playing {
            players[key]?.pause()
            stopEngineIfIdle()
            return
        }
        guard let player = player(for: key) else { return }
        player.node.volume = volume
        if !engine.isRunning {
            do { try engine.start() } catch { NSLog("Serenity: engine start failed: \(error)"); return }
        }
        player.play()
    }

    private func player(for key: String) -> LoopPlayer? {
        if let p = players[key] { return p }
        guard let url = Catalog.url(for: key), let file = try? AVAudioFile(forReading: url) else {
            NSLog("Serenity: missing sound file for \(key)")
            return nil
        }
        let p = LoopPlayer(file: file)
        engine.attach(p.node)
        engine.connect(p.node, to: engine.mainMixerNode, format: file.processingFormat)
        players[key] = p
        return p
    }

    private func stopEngineIfIdle() {
        if engine.isRunning && !players.values.contains(where: { $0.isPlaying }) {
            engine.pause()
        }
    }

    private func handleConfigurationChange() {
        // Output device changed (e.g. headphones). The engine stops; restart what was playing.
        let active = players.filter { $0.value.isPlaying }
        players.values.forEach { $0.reset() }
        guard !active.isEmpty else { return }
        do { try engine.start() } catch { return }
        active.values.forEach { $0.play() }
    }
}

private final class LoopPlayer {
    let node = AVAudioPlayerNode()
    let file: AVAudioFile
    private(set) var isPlaying = false
    private var scheduled = false
    private var generation = 0

    init(file: AVAudioFile) {
        self.file = file
    }

    func play() {
        guard !isPlaying else { return }
        if !scheduled {
            scheduled = true
            scheduleLoop(generation)
            scheduleLoop(generation)
        }
        node.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        node.pause()
        isPlaying = false
    }

    func reset() {
        generation += 1
        scheduled = false
        isPlaying = false
        node.stop()
    }

    private func scheduleLoop(_ gen: Int) {
        node.scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == gen, self.scheduled else { return }
                self.scheduleLoop(gen)
            }
        }
    }
}
