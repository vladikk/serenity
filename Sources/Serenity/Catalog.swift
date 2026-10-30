import Foundation

struct SoundInfo: Identifiable, Hashable {
    let key: String
    let label: String
    let symbol: String
    let sortKey: Int
    let defaultVisible: Bool
    let places: [String]

    var id: String { key }
}

/// Sound catalog mirroring asoftmurmur.com (labels, order and default visibility).
enum Catalog {
    static let all: [SoundInfo] = [
        SoundInfo(key: "rain", label: "Rain", symbol: "cloud.rain.fill", sortKey: 1, defaultVisible: true, places: ["the city", "the hills"]),
        SoundInfo(key: "thunder", label: "Thunder", symbol: "cloud.bolt.rain.fill", sortKey: 2, defaultVisible: true, places: ["the storm", "the valley"]),
        SoundInfo(key: "waves", label: "Waves", symbol: "water.waves", sortKey: 3, defaultVisible: true, places: ["the beach", "the coast", "the bay"]),
        SoundInfo(key: "wind", label: "Wind", symbol: "wind", sortKey: 4, defaultVisible: true, places: ["the moor", "the plains", "the mountains"]),
        SoundInfo(key: "fire", label: "Fire", symbol: "flame.fill", sortKey: 5, defaultVisible: true, places: ["the campfire", "the hearth", "the bonfire"]),
        SoundInfo(key: "birds", label: "Birds", symbol: "bird.fill", sortKey: 6, defaultVisible: true, places: ["the woods", "the park"]),
        SoundInfo(key: "crickets", label: "Crickets", symbol: "leaf.fill", sortKey: 7, defaultVisible: true, places: ["the meadow", "the prairie", "the pasture"]),
        SoundInfo(key: "people", label: "Coffee shop", symbol: "cup.and.saucer.fill", sortKey: 8, defaultVisible: true, places: ["the coffee shop", "the café", "the tearoom"]),
        SoundInfo(key: "sbowl", label: "Singing bowl", symbol: "bell.fill", sortKey: 9, defaultVisible: true, places: ["the temple", "the mountains", "Kyoto"]),
        SoundInfo(key: "whitenoise", label: "White noise", symbol: "waveform", sortKey: 10, defaultVisible: true, places: ["the power lines"]),
        SoundInfo(key: "raintrees", label: "Rain on trees", symbol: "tree.fill", sortKey: 11, defaultVisible: false, places: ["the forest", "the woods"]),
        SoundInfo(key: "raintinroof", label: "Rain on tin roof", symbol: "house.fill", sortKey: 12, defaultVisible: false, places: ["the shed", "the farm"]),
        SoundInfo(key: "raincabin", label: "Rain on cabin", symbol: "house.lodge.fill", sortKey: 13, defaultVisible: false, places: ["the cabin", "the lodge"]),
        SoundInfo(key: "stream", label: "Stream", symbol: "drop.fill", sortKey: 14, defaultVisible: false, places: ["the brook", "the creek"]),
        SoundInfo(key: "waterfall", label: "Waterfall", symbol: "mountain.2.fill", sortKey: 15, defaultVisible: false, places: ["the falls", "the gorge"]),
        SoundInfo(key: "cicadas", label: "Cicadas", symbol: "ladybug.fill", sortKey: 16, defaultVisible: false, places: ["the summer", "the orchard"]),
        SoundInfo(key: "chimesmetal", label: "Metal chimes", symbol: "bell.and.waves.left.and.right.fill", sortKey: 17, defaultVisible: false, places: ["the porch", "the garden"]),
        SoundInfo(key: "city", label: "City", symbol: "building.2.fill", sortKey: 18, defaultVisible: false, places: ["the city", "downtown"]),
        SoundInfo(key: "fanlow", label: "Fan on low", symbol: "fan", sortKey: 19, defaultVisible: false, places: ["the hotel", "home", "my house"]),
        SoundInfo(key: "fanhigh", label: "Fan on high", symbol: "fan.fill", sortKey: 20, defaultVisible: false, places: ["the hotel", "home", "my house"]),
        SoundInfo(key: "aircon", label: "Air conditioning", symbol: "air.conditioner.horizontal.fill", sortKey: 21, defaultVisible: false, places: ["the hotel", "home", "my house"]),
        SoundInfo(key: "frogs", label: "Frogs", symbol: "lizard.fill", sortKey: 22, defaultVisible: false, places: ["the swamp", "the pond", "the lagoon"]),
        SoundInfo(key: "clock", label: "Clock", symbol: "clock.fill", sortKey: 23, defaultVisible: false, places: ["the study", "the library"]),
        SoundInfo(key: "vinyl", label: "Record player", symbol: "record.circle", sortKey: 24, defaultVisible: false, places: ["the lounge", "the attic"]),
        SoundInfo(key: "brownnoise", label: "Brown noise", symbol: "waveform.path", sortKey: 99, defaultVisible: false, places: ["the void"]),
        SoundInfo(key: "pinknoise", label: "Pink noise", symbol: "waveform.path.ecg", sortKey: 100, defaultVisible: false, places: ["the void"]),
    ].sorted { $0.sortKey < $1.sortKey }

    static let byKey: [String: SoundInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static let noise: Set<String> = ["whitenoise", "pinknoise", "brownnoise"]

    static func url(for key: String) -> URL? {
        if let url = Bundle.main.url(forResource: key, withExtension: "mp4", subdirectory: "Sounds") {
            return url
        }
        // Fallback for `swift run` from the project directory.
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sounds/\(key).mp4")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}

enum MixNamer {
    private static let adjectives = ["soft", "gentle", "quiet", "misty", "warm", "drowsy", "calm", "hazy",
                                     "lazy", "distant", "mellow", "cosy", "still", "faded", "dreamy"]
    private static let times = ["day", "night", "morning", "afternoon", "evening", "sunset", "sunrise"]

    static func name(for keys: [String]) -> String {
        let adj = adjectives.randomElement()!
        let time = times.randomElement()!
        let place = keys.compactMap { Catalog.byKey[$0]?.places.randomElement() }.randomElement() ?? "somewhere"
        switch Int.random(in: 0..<3) {
        case 0: return "A \(adj) \(time)"
        case 1: return "A \(adj) \(time) in \(place)"
        default: return "\(adj.capitalized) \(place)".replacingOccurrences(of: " the ", with: " ")
        }
    }
}

struct SoundCredit: Decodable {
    struct Source: Decodable {
        let title: String
        let author: String
        let url: URL
        let license: String
        let licenseUrl: URL
    }

    let sources: [Source]?
    let generated: String?
}

/// Attribution for each sound, written by tools/build_sounds.py next to the sound files.
enum Credits {
    static let all: [String: SoundCredit] = {
        let url = Bundle.main.url(forResource: "credits", withExtension: "json", subdirectory: "Sounds")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sounds/credits.json")
        guard let data = try? Data(contentsOf: url),
              let credits = try? JSONDecoder().decode([String: SoundCredit].self, from: data) else { return [:] }
        return credits
    }()
}
