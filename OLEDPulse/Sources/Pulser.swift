import CoreGraphics
import Foundation

/// Schedules gamma pulses for one connected display.
final class Pulser {
    /// All gamma work runs on one serial queue so a pulse never reads another pulse's dimmed table as its base.
    private static let gammaQueue = DispatchQueue(label: "OLEDPulse.gamma", qos: .userInteractive)

    let displayID: CGDirectDisplayID
    let settings: PulseSettings
    private let shouldPulse: (CGDirectDisplayID) -> Bool
    private var timer: Timer?

    init(displayID: CGDirectDisplayID, settings: PulseSettings, shouldPulse: @escaping (CGDirectDisplayID) -> Bool) {
        self.displayID = displayID
        self.settings = settings
        self.shouldPulse = shouldPulse
    }

    func start() {
        let timer = Timer(timeInterval: settings.interval, repeats: true) { [weak self] _ in
            guard let self, self.shouldPulse(self.displayID) else { return }
            Pulser.pulse(display: self.displayID, settings: self.settings)
        }
        timer.tolerance = min(1, settings.interval / 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var nextPulseDate: Date? {
        timer?.fireDate
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func pulse(display: CGDirectDisplayID, settings: PulseSettings) {
        gammaQueue.async { run(display: display, settings: settings) }
    }

    private static func run(display: CGDirectDisplayID, settings: PulseSettings) {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return }
        var baseR = [CGGammaValue](repeating: 0, count: Int(capacity))
        var baseG = baseR, baseB = baseR
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &baseR, &baseG, &baseB, &count) == .success else { return }

        let depth = Float(settings.depth)
        func apply(strength k: Float) {
            func transform(_ v: CGGammaValue) -> CGGammaValue {
                switch settings.mode {
                case .scale: return v * (1 - depth * k)
                case .gamma: return pow(v, 1 + depth * k)
                }
            }
            CGSetDisplayTransferByTable(display, count, baseR.map(transform), baseG.map(transform), baseB.map(transform))
        }

        let refreshRate = CGDisplayCopyDisplayMode(display)?.refreshRate ?? 0
        let stepRate = refreshRate > 0 ? refreshRate : 60
        func ramp(from start: Float, to end: Float) {
            guard settings.ramp > 0 else { apply(strength: end); return }
            let steps = max(1, Int(settings.ramp * stepRate))
            for i in 1...steps {
                let t = Float(i) / Float(steps)
                apply(strength: start + (end - start) * t * t * (3 - 2 * t))
                Thread.sleep(forTimeInterval: settings.ramp / Double(steps))
            }
        }

        ramp(from: 0, to: 1)
        Thread.sleep(forTimeInterval: settings.hold)
        ramp(from: 1, to: 0)
        CGSetDisplayTransferByTable(display, count, baseR, baseG, baseB)
    }
}
