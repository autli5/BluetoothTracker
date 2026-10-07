import Cocoa
import IOBluetooth
import IOKit
import CoreAudio

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var appDelegateInstance: AppDelegate?
    
    private var statusItem: NSStatusItem!
    private let tracker = BluetoothTracker.shared
    private let updater = UpdaterService.shared
    private var refreshTimer: Timer?
    
    static func main() {
        if CommandLine.arguments.contains("--battery-probe") {
            runBatteryProbe()
            exit(0)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // Strong reference to prevent ARC deallocation of weak NSApplication.delegate
        appDelegateInstance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    
    private static func runBatteryProbe() {
        let isPowerOn = (IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON)
        print("POWER:\(isPowerOn ? 1 : 0)")
        guard isPowerOn else { exit(0) }
        
        typealias IntGetter = @convention(c) (AnyObject, Selector) -> Int
        func getInt(_ target: AnyObject, _ selName: String) -> Int? {
            let sel = Selector((selName))
            if target.responds(to: sel) {
                let imp = target.method(for: sel)
                let fn = unsafeBitCast(imp, to: IntGetter.self)
                let v = fn(target, sel)
                if v > 0 && v <= 100 { return v }
            }
            return nil
        }
        
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            let selPeer = Selector(("peer"))
            for dev in paired {
                let addr = dev.addressString ?? ""
                let name = dev.nameOrAddress ?? ""
                let connected = dev.isConnected()
                
                var single = getInt(dev, "batteryPercentSingle") ?? getInt(dev, "headsetBattery")
                var left = getInt(dev, "batteryPercentLeft")
                var right = getInt(dev, "batteryPercentRight")
                var bCase = getInt(dev, "batteryPercentCase")
                var combined = getInt(dev, "batteryPercentCombined")
                
                if dev.responds(to: selPeer),
                   let peer = dev.perform(selPeer)?.takeUnretainedValue() as? NSObject {
                    if single == nil { single = getInt(peer, "batteryPercentSingle") ?? getInt(peer, "headsetBattery") }
                    if left == nil { left = getInt(peer, "batteryPercentLeft") }
                    if right == nil { right = getInt(peer, "batteryPercentRight") }
                    if bCase == nil { bCase = getInt(peer, "batteryPercentCase") }
                    if combined == nil { combined = getInt(peer, "batteryPercentCombined") }
                }
                
                let sStr = single.map(String.init) ?? "-1"
                let lStr = left.map(String.init) ?? "-1"
                let rStr = right.map(String.init) ?? "-1"
                let cStr = bCase.map(String.init) ?? "-1"
                let combStr = combined.map(String.init) ?? "-1"
                
                print("DEV:\(addr):\(name):\(connected ? 1 : 0):\(sStr):\(lStr):\(rStr):\(cStr):\(combStr)")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create native status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Bluetooth Battery")
            button.imagePosition = .imageLeft
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
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
        
        // Regular safety UI sync timer in AppDelegate
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        RunLoop.main.add(t, forMode: .common)
        self.refreshTimer = t
        
        // Initial render
        updateStatusItem()
    }
    
    @objc private func handleTrackerUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItem()
        }
    }
    
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        
        if updater.isUpdating {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Updating")
            button.imagePosition = .imageLeft
            let text = updater.progressText.isEmpty ? "Обновление" : updater.progressText
            button.title = " \(updater.progressVisual) \(text)"
            return
        }
        
        let isPowerOn = tracker.isBluetoothPoweredOn
        let active = tracker.activeHeadphone ?? tracker.devices.first(where: { $0.isConnected && $0.primaryBatteryPercent != nil })
        let isConn = isPowerOn && (active?.isConnected == true)
        let percent = tracker.currentBatteryPercent ?? active?.primaryBatteryPercent
        
        if button.image == nil || button.image?.accessibilityDescription != "Bluetooth Battery" {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Bluetooth Battery")
        }
        button.imagePosition = .imageLeft
        
        if isConn, let p = percent, p > 0 {
            button.title = " \(p)%"
        } else {
            // When Bluetooth is off or headphones disconnected: show ONLY the headphones icon
            button.title = ""
        }
        
        statusItem.length = NSStatusItem.variableLength
        button.needsLayout = true
        button.needsDisplay = true
        
        let logLine = "[\(Date())] Dev: \(active?.name ?? "none") | Conn: \(isConn) | Power: \(isPowerOn) | Battery: \(percent.map(String.init) ?? "nil") | Title: '\(button.title)'\n"
        if let data = logLine.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/blts_live.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/blts_live.log"))
            }
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        buildMenu(menu)
    }
    
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let isPowerOn = tracker.isBluetoothPoweredOn
        let active = tracker.activeHeadphone ?? tracker.devices.first(where: { $0.isConnected && $0.primaryBatteryPercent != nil })
        
        if !isPowerOn {
            let item = NSMenuItem(title: "⚠️ Bluetooth выключен", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let dev = active, dev.isConnected {
            let batt = tracker.currentBatteryPercent ?? dev.primaryBatteryPercent
            let percentStr = batt != nil ? "\(batt!)%" : "Подключено"
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
        
        let updateTitle = updater.isUpdating ? "⏳ Обновление..." : "🌐 Обновить из GitHub"
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(updateClicked), keyEquivalent: "u")
        updateItem.target = self
        if updater.isUpdating { updateItem.isEnabled = false }
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Завершить", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func updateClicked() {
        updater.checkForUpdatesAndApply()
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
