import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = DisplayStore()
    private let activity = ActivityMonitor()
    private var statusItem: NSStatusItem!
    private var connected: [ConnectedDisplay] = []
    private var pulsers: [Pulser] = []
    private var countdownItems: [(item: NSMenuItem, pulser: Pulser)] = []
    private var countdownTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "OLED Pulse")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        registerLoginItemOnFirstLaunch()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        reloadPulsers()
    }

    @objc private func screensChanged() {
        reloadPulsers()
    }

    private func reloadPulsers() {
        pulsers.forEach { $0.stop() }
        pulsers = []
        connected = DisplayStore.connectedDisplays()
        for display in connected where store.saved[display.key] != nil {
            store.update(display.key) { $0.name = display.name }
        }
        statusItem.button?.appearsDisabled = !store.enabled
        guard store.enabled else { return }

        pulsers = connected.compactMap { display in
            guard let settings = store.saved[display.key] else { return nil }
            let pulser = Pulser(displayID: display.id, settings: settings) { [weak self] id in
                self?.shouldPulse(id) ?? false
            }
            pulser.start()
            return pulser
        }
    }

    private func shouldPulse(_ display: CGDirectDisplayID) -> Bool {
        store.enabled && activity.pauseReason == nil && !activity.isPlayingFullScreenVideo(on: display)
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshCountdowns() }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func refreshCountdowns() {
        for (item, pulser) in countdownItems {
            item.title = countdownTitle(pulser)
        }
    }

    private func countdownTitle(_ pulser: Pulser) -> String {
        guard let date = pulser.nextPulseDate else { return "Next pulse: not scheduled" }
        return "Next pulse in \(max(0, Int(date.timeIntervalSinceNow.rounded(.up))))s"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        countdownItems = []

        menu.addItem(ActionItem("Pulsing Enabled", checked: store.enabled) { [weak self] in
            guard let self else { return }
            self.store.enabled.toggle()
            self.reloadPulsers()
        })
        if store.enabled, let reason = activity.pauseReason {
            menu.addItem(disabledItem("Paused: \(reason)"))
        }

        let savedConnected = connected.compactMap { display in
            store.saved[display.key].map { (display.id, $0) }
        }
        let pulseAll = ActionItem("Pulse All Saved Displays Now") {
            for (id, settings) in savedConnected {
                Pulser.pulse(display: id, settings: settings)
            }
        }
        pulseAll.isEnabled = !savedConnected.isEmpty
        menu.addItem(pulseAll)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Connected Displays"))
        for display in connected {
            let item = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
            item.state = store.saved[display.key] != nil ? .on : .off
            item.submenu = displayMenu(key: display.key, connected: display)
            menu.addItem(item)
        }

        let connectedKeys = Set(connected.map(\.key))
        let disconnected = store.saved
            .filter { !connectedKeys.contains($0.key) }
            .sorted { $0.value.name.localizedStandardCompare($1.value.name) == .orderedAscending }
        if !disconnected.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Saved Displays (Not Connected)"))
            for (key, settings) in disconnected {
                let item = NSMenuItem(title: settings.name, action: nil, keyEquivalent: "")
                item.attributedTitle = NSAttributedString(
                    string: settings.name, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
                item.submenu = displayMenu(key: key, connected: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(loginItem())
        menu.addItem(ActionItem("Quit OLED Pulse") { NSApp.terminate(nil) })
    }

    private func displayMenu(key: String, connected display: ConnectedDisplay?) -> NSMenu {
        let menu = NSMenu()
        let settings = store.saved[key]

        if let display {
            menu.addItem(ActionItem("Pulse This Display", checked: settings != nil) { [weak self] in
                guard let self else { return }
                if self.store.saved[key] != nil { self.store.forget(key) } else { self.store.save(display) }
                self.reloadPulsers()
            })
        }

        guard let settings else { return menu }

        if let display {
            if let pulser = pulsers.first(where: { $0.displayID == display.id }) {
                let countdown = disabledItem(countdownTitle(pulser))
                countdownItems.append((countdown, pulser))
                menu.addItem(countdown)
            }
            menu.addItem(ActionItem("Test Pulse Now") {
                Pulser.pulse(display: display.id, settings: settings)
            })
        }

        menu.addItem(.separator())
        let modeItem = NSMenuItem(title: "Mode: \(modeTitle(settings.mode))", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in PulseMode.allCases {
            modeMenu.addItem(ActionItem(modeTitle(mode), checked: mode == settings.mode) { [weak self] in
                self?.change(key) { $0.mode = mode }
            })
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(numberMenu(
            "Depth", unit: "", current: settings.depth,
            options: [-0.5, -0.45, -0.4, -0.35, -0.3, -0.25, -0.2, -0.15, -0.1, -0.05,
                      0.05, 0.1, 0.15, 0.2, 0.25, 0.3], range: -0.9...0.9) { [weak self] v in
                self?.change(key) { $0.depth = v }
            })
        menu.addItem(numberMenu(
            "Ramp", unit: " s", current: settings.ramp,
            options: [0, 0.05, 0.1, 0.15, 0.25, 0.35, 0.4, 0.5, 0.6, 0.7, 0.8, 1], range: 0...5) { [weak self] v in
                self?.change(key) { $0.ramp = v }
            })
        menu.addItem(numberMenu(
            "Hold", unit: " s", current: settings.hold,
            options: [0, 0.01, 0.02, 0.03, 0.05, 0.075, 0.1, 0.2, 0.3], range: 0...5) { [weak self] v in
                self?.change(key) { $0.hold = v }
            })
        menu.addItem(numberMenu(
            "Interval", unit: " s", current: settings.interval,
            options: [30, 45, 60, 90, 120, 150, 180, 240, 300, 450, 600], range: 5...3600) { [weak self] v in
                self?.change(key) { $0.interval = v }
            })

        menu.addItem(.separator())
        menu.addItem(ActionItem("Reset to Defaults") { [weak self] in
            self?.change(key) { $0 = PulseSettings(name: $0.name) }
        })
        if display == nil {
            menu.addItem(ActionItem("Forget") { [weak self] in
                self?.store.forget(key)
                self?.reloadPulsers()
            })
        }
        return menu
    }

    private func change(_ key: String, _ update: (inout PulseSettings) -> Void) {
        store.update(key, update)
        reloadPulsers()
    }

    private func modeTitle(_ mode: PulseMode) -> String {
        switch mode {
        case .gamma: return "Gamma (midtones)"
        case .scale: return "Scale (brightness)"
        }
    }

    private func numberMenu(
        _ title: String, unit: String, current: Double, options: [Double], range: ClosedRange<Double>,
        set: @escaping (Double) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(format(current))\(unit)", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for option in options {
            menu.addItem(ActionItem("\(format(option))\(unit)", checked: option == current) { set(option) })
        }
        menu.addItem(.separator())
        let isCustom = !options.contains(current)
        let customTitle = isCustom ? "Custom (\(format(current))\(unit))…" : "Custom…"
        menu.addItem(ActionItem(customTitle, checked: isCustom) { [weak self] in
            if let value = self?.promptNumber(title, current: current, range: range) { set(value) }
        })
        item.submenu = menu
        return item
    }

    private func promptNumber(_ title: String, current: Double, range: ClosedRange<Double>) -> Double? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a value from \(format(range.lowerBound)) to \(format(range.upperBound))."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = format(current)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespaces)), range.contains(value) else {
            NSSound.beep()
            return nil
        }
        return value
    }

    private func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Login item

    private func registerLoginItemOnFirstLaunch() {
        let flag = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        try? SMAppService.mainApp.register()
    }

    private func loginItem() -> NSMenuItem {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            return ActionItem("Launch at Login (Needs Approval)…") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        return ActionItem("Launch at Login", checked: service.status == .enabled) {
            do {
                if service.status == .enabled { try service.unregister() } else { try service.register() }
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }
}

/// Menu item that runs a closure when chosen.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
