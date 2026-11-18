import AppKit

enum PulseMode: String, Codable, CaseIterable {
    case gamma, scale
}

struct PulseSettings: Codable, Equatable {
    var name: String
    var mode: PulseMode = .gamma
    var depth: Double = -0.3
    var ramp: Double = 0.5
    var hold: Double = 0.0
    var interval: Double = 180
}

struct ConnectedDisplay {
    let id: CGDirectDisplayID
    let key: String
    let name: String
}

/// Persists the overall toggle and the saved displays, keyed by vendor/model/serial so identical
/// monitors share settings.
final class DisplayStore {
    private let defaults = UserDefaults.standard
    private let savedKey = "savedDisplays"
    private let enabledKey = "enabled"

    private(set) var saved: [String: PulseSettings]

    var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    init() {
        if let data = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([String: PulseSettings].self, from: data) {
            saved = decoded
        } else {
            saved = [:]
        }
    }

    func save(_ display: ConnectedDisplay) {
        saved[display.key] = PulseSettings(name: display.name)
        persist()
    }

    func forget(_ key: String) {
        saved[key] = nil
        persist()
    }

    func update(_ key: String, _ change: (inout PulseSettings) -> Void) {
        guard var settings = saved[key] else { return }
        change(&settings)
        guard settings != saved[key] else { return }
        saved[key] = settings
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: savedKey)
        }
    }

    static func connectedDisplays() -> [ConnectedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
            return ConnectedDisplay(id: id, key: key, name: screen.localizedName)
        }
    }
}
