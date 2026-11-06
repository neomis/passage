import Foundation

/// Saves profiles as JSON in Application Support. Secrets are kept by the helper (see Secrets).
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedProfile") }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Passage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        selectedID = UserDefaults.standard.string(forKey: "selectedProfile") ?? ""
        load()
        if profile(selectedID) == nil { selectedID = profiles.first?.id ?? "" }
    }

    var selected: Profile? { profile(selectedID) }

    func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }

    // MARK: editing

    @discardableResult
    func add() -> Profile {
        var p = Profile()
        var n = 1
        while profiles.contains(where: { $0.name == p.name }) { n += 1; p.name = "New VPN \(n)" }
        profiles.append(p)
        if selectedID.isEmpty { selectedID = p.id }
        save()
        return p
    }

    func duplicate(_ id: String) -> Profile? {
        guard var p = profile(id) else { return nil }
        let oldID = p.id
        p.id = UUID().uuidString
        p.name += " copy"
        profiles.append(p)
        Secrets.copy(from: oldID, to: p.id)
        save()
        return p
    }

    func update(_ p: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
        save()
    }

    func delete(_ id: String) {
        profiles.removeAll { $0.id == id }
        Secrets.delete(id)
        if selectedID == id { selectedID = profiles.first?.id ?? "" }
        save()
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        // Fill in any settings added in newer versions with their defaults.
        let defaults = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Profile()))) as? [String: Any] ?? [:]
        profiles = raw.compactMap { stored in
            let merged = defaults.merging(stored) { _, new in new }
            guard let d = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
            return try? JSONDecoder().decode(Profile.self, from: d)
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
