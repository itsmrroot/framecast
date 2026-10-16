import Foundation

struct StylePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var style: Style
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var presets: [StylePreset] = []
    @Published private(set) var defaultStyle: Style = Style()

    private let url: URL
    private let defaultKey = "defaultStyle"

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Framecast", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("presets.json")
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            presets = arr.compactMap { obj in
                guard let name = obj["name"] as? String else { return nil }
                let id = (obj["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                let style = decodeWithDefaults(Style.self, from: obj["style"] ?? [:], defaults: Style())
                return StylePreset(id: id, name: name, style: style)
            }
        }
        if let data = UserDefaults.standard.data(forKey: defaultKey),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            defaultStyle = decodeWithDefaults(Style.self, from: obj, defaults: Style())
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func add(name: String, style: Style) {
        presets.append(StylePreset(name: name, style: style))
        persist()
    }

    func remove(_ preset: StylePreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func setDefault(_ style: Style) {
        defaultStyle = style
        if let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: defaultKey)
        }
    }
}
