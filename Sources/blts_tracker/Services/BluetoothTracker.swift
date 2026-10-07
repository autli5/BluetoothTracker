import Foundation
import IOBluetooth
import IOKit
import CoreAudio
import AudioToolbox

public final class BluetoothTracker: ObservableObject {
    public static let shared = BluetoothTracker()
    public static let didUpdateNotification = Notification.Name("BLTSTrackerDidUpdateNotification")
    
    @Published public var activeHeadphone: BluetoothDeviceModel?
    @Published public var devices: [BluetoothDeviceModel] = []
    
    // Direct primitive properties for instant reactivity
    @Published public var currentBatteryPercent: Int?
    @Published public var currentDeviceName: String = ""
    @Published public var isConnected: Bool = false
    @Published public var isBluetoothPoweredOn: Bool = true
    
    private var timerSource: DispatchSourceTimer?
    private var knownBatteries: [String: Int] = [:]
    private typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
    
    public static func checkBluetoothPower() -> Bool {
        guard let controller = IOBluetoothHostController.default() else { return false }
        return controller.powerState == kBluetoothHCIPowerStateON
    }
    
    public init() {
        self.isBluetoothPoweredOn = BluetoothTracker.checkBluetoothPower()
        setupBluetoothListeners()
        startTracking()
    }
    
    deinit {
        stopTracking()
    }
    
    public func startTracking() {
        stopTracking()
        updateDeviceList()
        pollSubprocessProbe()
        
        // Strict 1.0s timer for probe monitoring (with zero-flicker authoritative updates)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if !BluetoothTracker.checkBluetoothPower() {
                self.applyPowerOffState()
            } else {
                self.pollSubprocessProbe()
            }
        }
        timer.resume()
        self.timerSource = timer
    }
    
    public func stopTracking() {
        timerSource?.cancel()
        timerSource = nil
    }
    
    private var isProbeRunning = false
    
    private func resolveProbeBinary() -> (String, [String])? {
        // 1. Same directory as current executable
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            let dedicated = "\(exeDir)/battery_probe"
            if FileManager.default.isExecutableFile(atPath: dedicated) {
                return (dedicated, [])
            }
        }
        
        // 2. App bundle path in project directory
        let bundleProbe = "/Users/autli/Documents/blts_tracker/BLTS Tracker.app/Contents/MacOS/battery_probe"
        if FileManager.default.isExecutableFile(atPath: bundleProbe) {
            return (bundleProbe, [])
        }
        
        // 3. Current executable only if named blts_tracker
        if let exePath = Bundle.main.executablePath,
           exePath.hasSuffix("blts_tracker"),
           FileManager.default.isExecutableFile(atPath: exePath) {
            return (exePath, ["--battery-probe"])
        }
        
        return nil
    }
    
    public func pollSubprocessProbe() {
        guard !isProbeRunning else { return }
        
        if !BluetoothTracker.checkBluetoothPower() {
            applyPowerOffState()
            return
        }
        
        guard let (binary, probeArgs) = resolveProbeBinary() else { return }
        
        isProbeRunning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { self?.isProbeRunning = false }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = probeArgs
            let pipe = Pipe()
            proc.standardOutput = pipe
            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    self?.parseProbeOutput(output)
                }
            } catch {
                // Ignore probe errors
            }
        }
    }
    
    private struct ProbeDev {
        let address: String
        let name: String
        let isConnected: Bool
        let singleBattery: Int?
        let leftBattery: Int?
        let rightBattery: Int?
        let caseBattery: Int?
        let combinedBattery: Int?
    }
    
    private func parseProbeOutput(_ output: String) {
        var powerOn: Bool = true
        var devMap: [String: ProbeDev] = [:]
        
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("POWER:") {
                let val = trimmed.replacingOccurrences(of: "POWER:", with: "")
                powerOn = (val == "1")
            } else if trimmed.hasPrefix("DEV:") {
                let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count >= 8 {
                    let addr = String(parts[1])
                    let name = String(parts[2])
                    let conn = parts[3] == "1"
                    let single = Int(parts[4]).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
                    let left = Int(parts[5]).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
                    let right = Int(parts[6]).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
                    let bCase = Int(parts[7]).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
                    let comb = (parts.count > 8 ? Int(parts[8]) : nil).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
                    
                    devMap[addr] = ProbeDev(
                        address: addr,
                        name: name,
                        isConnected: conn,
                        singleBattery: single,
                        leftBattery: left,
                        rightBattery: right,
                        caseBattery: bCase,
                        combinedBattery: comb
                    )
                }
            }
        }
        
        let applyBlock = { [weak self] in
            guard let self = self else { return }
            if !powerOn {
                self.applyPowerOffState()
            } else {
                self.applyProbeDevices(devMap)
            }
        }
        
        if Thread.isMainThread {
            applyBlock()
        } else {
            DispatchQueue.main.async(execute: applyBlock)
        }
    }
    
    private func applyPowerOffState() {
        var changed = false
        if self.isBluetoothPoweredOn {
            self.isBluetoothPoweredOn = false
            changed = true
        }
        if self.isConnected {
            self.isConnected = false
            changed = true
        }
        if self.currentBatteryPercent != nil {
            self.currentBatteryPercent = nil
            changed = true
        }
        if !self.currentDeviceName.isEmpty {
            self.currentDeviceName = ""
            changed = true
        }
        if self.activeHeadphone != nil {
            self.activeHeadphone = nil
            changed = true
        }
        self.knownBatteries.removeAll()
        for i in 0..<self.devices.count {
            if self.devices[i].isConnected {
                self.devices[i].isConnected = false
                changed = true
            }
            if self.devices[i].singleBattery != nil {
                self.devices[i].singleBattery = nil
                changed = true
            }
        }
        if changed {
            self.objectWillChange.send()
            NotificationCenter.default.post(name: BluetoothTracker.didUpdateNotification, object: self)
        }
    }
    
    private func applyProbeDevices(_ devMap: [String: ProbeDev]) {
        var changed = false
        if !self.isBluetoothPoweredOn {
            self.isBluetoothPoweredOn = true
            changed = true
        }
        
        for i in 0..<devices.count {
            let addr = devices[i].address
            if let p = devMap[addr] {
                if devices[i].isConnected != p.isConnected {
                    devices[i].isConnected = p.isConnected
                    changed = true
                }
                if p.isConnected {
                    if let fresh = p.singleBattery, fresh > 0 && fresh <= 100 {
                        if devices[i].singleBattery != fresh {
                            devices[i].singleBattery = fresh
                            knownBatteries[addr] = fresh
                            changed = true
                        }
                    }
                    if let l = p.leftBattery, devices[i].leftBattery != l {
                        devices[i].leftBattery = l
                        changed = true
                    }
                    if let r = p.rightBattery, devices[i].rightBattery != r {
                        devices[i].rightBattery = r
                        changed = true
                    }
                    if let c = p.caseBattery, devices[i].caseBattery != c {
                        devices[i].caseBattery = c
                        changed = true
                    }
                    if let comb = p.combinedBattery, devices[i].combinedBattery != comb {
                        devices[i].combinedBattery = comb
                        changed = true
                    }
                } else {
                    knownBatteries.removeValue(forKey: addr)
                    if devices[i].singleBattery != nil {
                        devices[i].singleBattery = nil
                        changed = true
                    }
                }
            }
        }
        
        // Enrich connected devices from IOKit
        enrichFromIORegistry(devices: &devices)
        
        let foundActive = devices.first(where: { $0.isConnected && $0.isAudioDevice })
            ?? devices.first(where: { $0.isConnected })
        
        if activeHeadphone?.address != foundActive?.address {
            activeHeadphone = foundActive
            changed = true
        }
        
        let newPercent = foundActive?.primaryBatteryPercent
        if currentBatteryPercent != newPercent {
            currentBatteryPercent = newPercent
            changed = true
        }
        
        let newName = foundActive?.name ?? ""
        if currentDeviceName != newName {
            currentDeviceName = newName
            changed = true
        }
        
        let newConn = foundActive?.isConnected == true
        if isConnected != newConn {
            isConnected = newConn
            changed = true
        }
        
        if changed {
            objectWillChange.send()
            NotificationCenter.default.post(name: BluetoothTracker.didUpdateNotification, object: self)
        }
    }
    
    public func refreshNow() {
        if !BluetoothTracker.checkBluetoothPower() {
            applyPowerOffState()
        } else {
            updateDeviceList()
            pollSubprocessProbe()
        }
    }
    
    private func setupBluetoothListeners() {
        let notificationNames = [
            "IOBluetoothDeviceWasConnectedNotification",
            "IOBluetoothDeviceWasDisconnectedNotification",
            "IOBluetoothDeviceNotification",
            "IOBluetoothDeviceServicesResolvedNotification",
            "IOBluetoothDeviceNameChangedNotification",
            "IOBluetoothHandsFreeDeviceDidUpdateNotification"
        ]
        
        for name in notificationNames {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBluetoothChange),
                name: NSNotification.Name(name),
                object: nil
            )
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleBluetoothChange),
            name: NSNotification.Name("com.apple.Bluetooth.status"),
            object: nil
        )
    }
    
    @objc private func handleBluetoothChange() {
        refreshNow()
    }
    
    public func updateDeviceList() {
        let powerOn = BluetoothTracker.checkBluetoothPower()
        self.isBluetoothPoweredOn = powerOn
        
        if !powerOn {
            applyPowerOffState()
            return
        }
        
        var updatedList: [BluetoothDeviceModel] = []
        
        // 1. Scan IOBluetooth paired devices catalogue
        if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for pairedDev in pairedDevices {
                let address = pairedDev.addressString ?? UUID().uuidString
                let name = pairedDev.nameOrAddress ?? "Unknown Device"
                let majorClass = UInt32(pairedDev.deviceClassMajor)
                let minorClass = UInt32(pairedDev.deviceClassMinor)
                let isAudio = (majorClass == 4) || isLikelyHeadphones(name: name, minorClass: minorClass, majorClass: majorClass)
                
                var isMulti = false
                let selMulti = Selector(("isMultiBatteryDevice"))
                if pairedDev.responds(to: selMulti) {
                    let imp = pairedDev.method(for: selMulti)
                    let fn = unsafeBitCast(imp, to: BoolGetter.self)
                    isMulti = fn(pairedDev, selMulti)
                }
                
                // IMPORTANT: Strictly preserve isConnected and battery from the authoritative probe!
                // NEVER query stale in-process IOBluetoothDevice ivars to avoid flickering!
                let existing = self.devices.first(where: { $0.address == address })
                let isConn = existing?.isConnected ?? false
                
                var model = BluetoothDeviceModel(
                    name: name,
                    address: address,
                    isConnected: isConn,
                    isAudioDevice: isAudio,
                    isMultiBattery: isMulti,
                    majorClass: majorClass,
                    minorClass: minorClass,
                    lastUpdated: Date()
                )
                
                if isConn {
                    model.singleBattery = existing?.singleBattery
                    model.leftBattery = existing?.leftBattery
                    model.rightBattery = existing?.rightBattery
                    model.caseBattery = existing?.caseBattery
                    model.combinedBattery = existing?.combinedBattery
                }
                
                updatedList.append(model)
            }
        }
        
        // 2. Sort: Connected audio first
        updatedList.sort { d1, d2 in
            if d1.isConnected != d2.isConnected {
                return d1.isConnected && !d2.isConnected
            }
            if d1.isAudioDevice != d2.isAudioDevice {
                return d1.isAudioDevice && !d2.isAudioDevice
            }
            return d1.name.localizedCaseInsensitiveCompare(d2.name) == .orderedAscending
        }
        
        self.devices = updatedList
        
        let foundActive = updatedList.first(where: { $0.isConnected && $0.isAudioDevice })
            ?? updatedList.first(where: { $0.isConnected })
        
        self.activeHeadphone = foundActive
        self.currentBatteryPercent = foundActive?.primaryBatteryPercent
        self.currentDeviceName = foundActive?.name ?? ""
        self.isConnected = (foundActive?.isConnected == true)
        
        self.objectWillChange.send()
        NotificationCenter.default.post(name: BluetoothTracker.didUpdateNotification, object: self)
    }
    
    public func getActiveCoreAudioDeviceName() -> String? {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )

        guard status == noErr else { return nil }
        
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceName: CFString = "" as CFString
        let nameStatus = withUnsafeMutablePointer(to: &deviceName) { ptr in
            AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                ptr
            )
        }
        if nameStatus == noErr {
            return deviceName as String
        }
        return nil
    }
    
    public func isLikelyHeadphones(name: String, minorClass: UInt32, majorClass: UInt32 = 0) -> Bool {
        let lower = name.lowercased()
        let nonAudioKeywords = ["mouse", "keyboard", "trackpad", "pen", "pencil", "watch"]
        for nonKw in nonAudioKeywords {
            if lower.contains(nonKw) { return false }
        }
        
        let keywords = ["buds", "pods", "freebuds", "airpods", "headphone", "headset", "earphone", "earbuds", "wh-", "wf-", "qc", "bose", "sony", "jbl", "beats", "marshall", "sennheiser", "soundcore", "pixel buds", "galaxy buds"]
        for kw in keywords {
            if lower.contains(kw) { return true }
        }
        if majorClass == 4 && (minorClass >= 1 && minorClass <= 6) {
            return true
        }
        return false
    }
    
    private func enrichFromIORegistry(devices: inout [BluetoothDeviceModel]) {
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                
                let prodName = dict["Product"] as? String ?? dict["DeviceName"] as? String
                let addr = dict["DeviceAddress"] as? String
                let batt = dict["BatteryPercent"] as? Int
                let battLeft = dict["BatteryPercentLeft"] as? Int
                let battRight = dict["BatteryPercentRight"] as? Int
                let battCase = dict["BatteryPercentCase"] as? Int
                
                for i in 0..<devices.count {
                    // Only enrich if the device is actually connected!
                    guard devices[i].isConnected else { continue }
                    
                    let matchByName = prodName != nil && devices[i].name.caseInsensitiveCompare(prodName!) == .orderedSame
                    let matchByAddr = addr != nil && devices[i].address.replacingOccurrences(of: "-", with: ":").caseInsensitiveCompare(addr!.replacingOccurrences(of: "-", with: ":")) == .orderedSame
                    
                    if matchByName || matchByAddr {
                        if let b = batt, b > 0 && b <= 100 {
                            devices[i].singleBattery = b
                            knownBatteries[devices[i].address] = b
                        }
                        if devices[i].isMultiBattery {
                            if let bl = battLeft, bl > 0 && bl <= 100 {
                                devices[i].leftBattery = bl
                            }
                            if let br = battRight, br > 0 && br <= 100 {
                                devices[i].rightBattery = br
                            }
                            if let bc = battCase, bc > 0 && bc <= 100 {
                                devices[i].caseBattery = bc
                            }
                        }
                    }
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }
}
