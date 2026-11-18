// Periodically perturbs the LG display's gamma table to jog the panel's static-content dimmer.
//
// Build: swiftc -O tools/GammaPulse.swift -o gamma-pulse
// Usage: ./gamma-pulse [--interval 45] [--depth 0.10] [--hold 0.3] [--ramp 0] [--mode scale|gamma] [--once]
//   --mode scale  multiplies every output level by (1 - depth), like a brightness dip
//   --mode gamma  raises the curve to the power (1 + depth): whites stay put, mids/shadows move
//                 (negative depth brightens mids instead)
//   --ramp        seconds to ease in and out; 0 applies the change in a single frame

import CoreGraphics
import Foundation

enum Mode: String { case scale, gamma }

var interval = 45.0
var depth: Float = 0.10
var hold = 0.3
var ramp = 0.0
var mode = Mode.scale
var once = false

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    func value() -> String {
        guard let v = args.next() else { fatalError("missing value for \(arg)") }
        return v
    }
    switch arg {
    case "--interval": interval = Double(value())!
    case "--depth": depth = Float(value())!
    case "--hold": hold = Double(value())!
    case "--ramp": ramp = Double(value())!
    case "--mode": mode = Mode(rawValue: value()) ?? { fatalError("unknown mode") }()
    case "--once": once = true
    default: fatalError("unknown argument \(arg)")
    }
}

let lgVendorID: UInt32 = 7789

func findDisplay() -> CGDirectDisplayID {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    guard let id = ids.first(where: { CGDisplayVendorNumber($0) == lgVendorID }) else {
        fatalError("LG display not found")
    }
    return id
}

let display = findDisplay()
let capacity = CGDisplayGammaTableCapacity(display)
var baseR = [CGGammaValue](repeating: 0, count: Int(capacity))
var baseG = baseR, baseB = baseR
var sampleCount: UInt32 = 0
guard CGGetDisplayTransferByTable(display, capacity, &baseR, &baseG, &baseB, &sampleCount) == .success else {
    fatalError("could not read gamma table")
}

func apply(strength k: Float) {
    func transform(_ v: CGGammaValue) -> CGGammaValue {
        switch mode {
        case .scale: return v * (1 - depth * k)
        case .gamma: return pow(v, 1 + depth * k)
        }
    }
    let r = baseR.map(transform), g = baseG.map(transform), b = baseB.map(transform)
    CGSetDisplayTransferByTable(display, sampleCount, r, g, b)
}

func restore() {
    CGSetDisplayTransferByTable(display, sampleCount, baseR, baseG, baseB)
}

func easeRamp(from a: Float, to b: Float) {
    guard ramp > 0 else { apply(strength: b); return }
    let steps = max(1, Int(ramp * 60))
    for i in 1...steps {
        let t = Float(i) / Float(steps)
        let eased = t * t * (3 - 2 * t)
        apply(strength: a + (b - a) * eased)
        Thread.sleep(forTimeInterval: ramp / Double(steps))
    }
}

func pulse() {
    easeRamp(from: 0, to: 1)
    Thread.sleep(forTimeInterval: hold)
    easeRamp(from: 1, to: 0)
    restore()
    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("\(stamp) pulse")
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { restore(); exit(0) }
    source.resume()
    signalSources.append(source)
}

print("display \(display): \(mode.rawValue) depth \(depth), hold \(hold)s, ramp \(ramp)s, every \(interval)s")

Thread.detachNewThread {
    if once {
        pulse()
        exit(0)
    }
    while true {
        Thread.sleep(forTimeInterval: interval)
        pulse()
    }
}
dispatchMain()
