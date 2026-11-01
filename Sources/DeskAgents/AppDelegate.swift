import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var stage: Stage!
    private var statusItem: NSStatusItem!
    private let defaults = UserDefaults.standard

    private var enabledKinds: [AgentKind] {
        get {
            guard let saved = defaults.stringArray(forKey: "enabledAgents") else { return AgentKind.allCases }
            return AgentKind.allCases.filter { saved.contains($0.rawValue) }
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "enabledAgents") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)  // already running
            return
        }

        stage = Stage()
        stage.placement = Placement(rawValue: defaults.string(forKey: "placement") ?? "") ?? .desktop
        stage.liveChatter = defaults.bool(forKey: "liveChatter")
        stage.setEnabled(enabledKinds)
        stage.menuProvider = { [unowned self] in
            let menu = NSMenu()
            self.fill(menu)
            return menu
        }
        stage.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Desk Agents")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Agents"))
        for kind in AgentKind.allCases {
            let item = item(kind.name, #selector(toggleAgent(_:)), on: enabledKinds.contains(kind))
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Where they live"))
        let desktop = item("On the Desktop", #selector(setPlacement(_:)), on: stage.placement == .desktop)
        desktop.representedObject = Placement.desktop.rawValue
        menu.addItem(desktop)
        let top = item("Above All Windows", #selector(setPlacement(_:)), on: stage.placement == .top)
        top.representedObject = Placement.top.rawValue
        menu.addItem(top)

        menu.addItem(.separator())
        menu.addItem(item("Call Them Over", #selector(callOver)))
        menu.addItem(item("Real Small Talk (uses quota)", #selector(toggleLiveChatter), on: stage.liveChatter))
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Desk Agents", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func toggleAgent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = AgentKind(rawValue: raw) else { return }
        var kinds = enabledKinds
        if let i = kinds.firstIndex(of: kind) { kinds.remove(at: i) } else { kinds.append(kind) }
        enabledKinds = kinds
        stage.setEnabled(enabledKinds)
    }

    @objc private func setPlacement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let placement = Placement(rawValue: raw) else { return }
        stage.placement = placement
        defaults.set(raw, forKey: "placement")
    }

    @objc private func callOver() { stage.callOver() }

    @objc private func toggleLiveChatter() {
        stage.liveChatter.toggle()
        defaults.set(stage.liveChatter, forKey: "liveChatter")
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
