import AppKit
import IOKit.pwr_mgt

/// Closure-backed menu item target.
final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

extension NSMenu {
    @discardableResult
    func add(_ title: String, checked: Bool = false, keep: inout [MenuAction], _ run: @escaping () -> Void) -> NSMenuItem {
        let box = MenuAction(run)
        keep.append(box)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = box
        item.state = checked ? .on : .off
        addItem(item)
        return item
    }

    func addHeader(_ title: String) {
        let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        h.isEnabled = false
        addItem(h)
    }
}

/// Keeps the Mac awake with power assertions. Own menu-bar icon, like the reference menu.
final class Caffeinate: NSObject, NSMenuDelegate {
    static let shared = Caffeinate()

    enum Choice: Equatable {
        case indefinite
        case minutes(Int)
        case until(Date)
    }

    static let presets: [(String, Int)] = [("10 Minutes", 10), ("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120),
                                           ("4 Hours", 240), ("8 Hours", 480), ("12 Hours", 720)]

    private(set) var choice: Choice?
    private(set) var endsAt: Date?
    var isActive: Bool { choice != nil }

    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var keep: [MenuAction] = []

    func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshIcon()
    }

    // MARK: control

    func start(_ c: Choice) {
        stop()
        let keepDisplay = Settings.shared.data.caffeinateKeepDisplay
        let types = keepDisplay ? [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertPreventUserIdleSystemSleep]
                                : [kIOPMAssertPreventUserIdleSystemSleep]
        for t in types {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(t as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Nexus Caffeinate" as CFString, &id) == kIOReturnSuccess { assertions.append(id) }
        }
        guard !assertions.isEmpty else { return }
        choice = c
        switch c {
        case .indefinite: endsAt = nil
        case .minutes(let m): endsAt = Date().addingTimeInterval(Double(m) * 60)
        case .until(let d): endsAt = d
        }
        if let end = endsAt {
            let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.stop() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        refreshIcon()
    }

    func stop() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        timer?.invalidate(); timer = nil
        choice = nil; endsAt = nil
        refreshIcon()
    }

    func toggle() { isActive ? stop() : start(.indefinite) }

    private func refreshIcon() {
        guard let b = statusItem?.button else { return }
        b.image = NSImage(systemSymbolName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: "Caffeinate")
        if let end = endsAt {
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            b.toolTip = "Awake until \(f.string(from: end))"
        } else {
            b.toolTip = isActive ? "Awake indefinitely" : "Caffeinate"
        }
    }

    // MARK: menu (mirrors the reference: Decaffeinate, Caffeinate header, durations, Until…)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        keep.removeAll()
        if isActive {
            menu.add("Decaffeinate", keep: &keep) { [weak self] in self?.stop() }
            menu.addItem(.separator())
        }
        menu.addHeader("Caffeinate")
        menu.add("Indefinitely", checked: choice == .indefinite, keep: &keep) { [weak self] in self?.start(.indefinite) }
        for (title, m) in Self.presets {
            menu.add(title, checked: choice == .minutes(m), keep: &keep) { [weak self] in self?.start(.minutes(m)) }
        }
        menu.addItem(.separator())
        var untilTitle = "Until…"
        var untilChecked = false
        if case .until(let d)? = choice {
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            untilTitle = "Until \(f.string(from: d))…"; untilChecked = true
        }
        menu.add(untilTitle, checked: untilChecked, keep: &keep) { [weak self] in self?.promptUntil() }
    }

    private func promptUntil() {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.dateValue = Date().addingTimeInterval(3600)
        let alert = NSAlert()
        alert.messageText = "Keep awake until"
        alert.informativeText = "Pick a time. If it has already passed today, it means tomorrow."
        alert.accessoryView = picker
        alert.addButton(withTitle: "Caffeinate")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        start(.until(Self.nextOccurrence(of: picker.dateValue)))
    }

    /// The next moment (today, else tomorrow) whose time of day matches `time`.
    static func nextOccurrence(of time: Date, now: Date = Date(), calendar cal: Calendar = .current) -> Date {
        let hm = cal.dateComponents([.hour, .minute], from: time)
        return cal.nextDate(after: now, matching: hm, matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
    }
}
