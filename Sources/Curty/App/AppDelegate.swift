import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()

    private var panelController: PanelController?
    private var statusItem: NSStatusItem?
    private weak var clipboardMenuItem: NSMenuItem?
    private weak var pinMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PanelController(model: model)
        panelController?.install()
        installMenuBarItem()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        panelController?.teardown()
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Curty")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Открыть Curty", action: #selector(togglePanel), keyEquivalent: "")

        let pin = menu.addItem(withTitle: "Закрепить панель", action: #selector(togglePin), keyEquivalent: "")
        pinMenuItem = pin

        let clipboard = menu.addItem(withTitle: "Наблюдать за буфером", action: #selector(toggleClipboard), keyEquivalent: "")
        clipboardMenuItem = clipboard

        menu.addItem(.separator())
        // Без keyEquivalent: у приложения без строки меню сочетания работают
        // только при открытом меню, то есть обещают то, чего нет.
        menu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Завершить Curty", action: #selector(quit), keyEquivalent: "")

        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        clipboardMenuItem?.state = model.preferences.clipboardMonitoringEnabled ? .on : .off
        pinMenuItem?.state = model.isPinned ? .on : .off
    }

    @objc private func togglePanel() { panelController?.toggle(holdingUntilCursorArrives: true) }

    @objc private func togglePin() {
        model.isPinned.toggle()
        if model.isPinned { panelController?.open() }
    }

    @objc private func toggleClipboard() {
        model.preferences.clipboardMonitoringEnabled.toggle()
    }

    @objc private func openSettings() {
        model.select(.settings)
        panelController?.open(holdingUntilCursorArrives: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
