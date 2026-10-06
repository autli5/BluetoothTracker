import Cocoa
import IOBluetooth
import IOKit
import CoreAudio

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let tracker = BluetoothTracker.shared
    private let updater = UpdaterService.shared
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create native status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Bluetooth Battery")
            button.imagePosition = .imageLeft
        }
        
        setupMenu()
        
        // Listen to real-time tracker updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackerUpdate),
            name: BluetoothTracker.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackerUpdate),
            name: UpdaterService.didUpdateStateNotification,
            object: nil
        )
        
        // Start active tracking
        tracker.startTracking()
        
        // Initial render
        updateStatusItem()
    }
    
    @objc private func handleTrackerUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
            self?.setupMenu()
        }
    }
    
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        
        if updater.isUpdating {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Updating")
            let text = updater.progressText.isEmpty ? "Обновление" : updater.progressText
            button.title = " \(updater.progressVisual) \(text)"
            return
        }
        
        let active = tracker.activeHeadphone
        let isConn = active?.isConnected == true
        let percent = active?.primaryBatteryPercent
        
        button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Bluetooth Battery")
        
        if isConn, let p = percent, p > 0 {
            button.title = " \(p)%"
        } else {
            button.title = ""
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let active = tracker.activeHeadphone
        if let dev = active, dev.isConnected {
            let percentStr = dev.primaryBatteryPercent != nil ? "\(dev.primaryBatteryPercent!)%" : "Подключено"
            let titleItem = NSMenuItem(title: "🎧 \(dev.name): \(percentStr)", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            
            if let l = dev.leftBattery, let r = dev.rightBattery {
                let subItem = NSMenuItem(title: "   Левый: \(l)% | Правый: \(r)%", action: nil, keyEquivalent: "")
                subItem.isEnabled = false
                menu.addItem(subItem)
            }
        } else {
            let item = NSMenuItem(title: "🎧 Наушники не подключены", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "🔄 Обновить заряд", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let updateTitle = updater.isUpdating ? "⏳ Обновление..." : "🌐 Обновить из GitHub"
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(updateClicked), keyEquivalent: "u")
        updateItem.target = self
        if updater.isUpdating { updateItem.isEnabled = false }
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Завершить", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func refreshClicked() {
        tracker.refreshNow()
    }
    
    @objc private func updateClicked() {
        updater.checkForUpdatesAndApply()
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
