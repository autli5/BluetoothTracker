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
    
    private var timerSource: DispatchSourceTimer?
    
    private typealias IntBatteryGetter = @convention(c) (AnyObject, Selector) -> Int
    private typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
    
    public init() {
        setupBluetoothListeners()
        startTracking()
    }
    
    deinit {
        stopTracking()
    }
    
    public func startTracking() {
        stopTracking()
        updateDeviceList()
        
        // Kernel-level DispatchSourceTimer: strictly 1 second interval, no caching
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.updateDeviceList()
        }
        timer.resume()
        self.timerSource = timer
    }
    
    public func stopTracking() {
        timerSource?.cancel()
        timerSource = nil
    }
    
    public func refreshNow() {
        updateDeviceList()
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
    }
    
    @objc private func handleBluetoothChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateDeviceList()
        }
        for delay in [0.2, 0.5, 1.0, 1.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateDeviceList()
            }
        }
    }
    
    public func updateDeviceList() {
        var updatedList: [BluetoothDeviceModel] = []
        let activeAudioName = getActiveCoreAudioDeviceName()
        
        // 1. Scan IOBluetooth paired devices directly (zero caching)
        if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for pairedDev in pairedDevices {
                let address = pairedDev.addressString ?? UUID().uuidString
                let device = IOBluetoothDevice(addressString: address) ?? pairedDev
                let name = device.nameOrAddress ?? pairedDev.nameOrAddress ?? "Unknown Device"
                
                let isAudioOutput = activeAudioName != nil && (
                    name.caseInsensitiveCompare(activeAudioName!) == .orderedSame ||
                    activeAudioName!.localizedCaseInsensitiveContains(name) ||
                    name.localizedCaseInsensitiveContains(activeAudioName!)
                )
                let isConnected = device.isConnected() || pairedDev.isConnected() || isAudioOutput
                
                let majorClass = UInt32(device.deviceClassMajor)
                let minorClass = UInt32(device.deviceClassMinor)
                let isAudio = (majorClass == 4) || isLikelyHeadphones(name: name, minorClass: minorClass, majorClass: majorClass) || isAudioOutput
                
                var isMulti = false
                let selMulti = Selector(("isMultiBatteryDevice"))
                if device.responds(to: selMulti) {
                    let imp = device.method(for: selMulti)
                    let fn = unsafeBitCast(imp, to: BoolGetter.self)
                    isMulti = fn(device, selMulti)
                }
                
                var model = BluetoothDeviceModel(
                    name: name,
                    address: address,
                    isConnected: isConnected,
                    isAudioDevice: isAudio,
                    isMultiBattery: isMulti,
                    majorClass: majorClass,
                    minorClass: minorClass,
                    lastUpdated: Date()
                )
                
                if isConnected {
                    extractBatteryLevels(from: device, fallbackDevice: pairedDev, into: &model, isMulti: isMulti)
                }
                
                updatedList.append(model)
            }
        }
        
        // 2. IOKit Registry live enrich (zero caching)
        enrichFromIORegistry(devices: &updatedList)
        
        // 3. Sort: Connected audio first
        updatedList.sort { d1, d2 in
            if d1.isConnected != d2.isConnected {
                return d1.isConnected && !d2.isConnected
            }
            if d1.isAudioDevice != d2.isAudioDevice {
                return d1.isAudioDevice && !d2.isAudioDevice
            }
            return d1.name.localizedCaseInsensitiveCompare(d2.name) == .orderedAscending
        }
        
        let foundActive = updatedList.first(where: { $0.isConnected && $0.isAudioDevice })
            ?? updatedList.first(where: { $0.isConnected })
        
        let newPercent = foundActive?.primaryBatteryPercent
        let newName = foundActive?.name ?? ""
        let newConnected = foundActive?.isConnected == true
        
        let applyUpdate = { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            self.devices = updatedList
            self.activeHeadphone = foundActive
            self.currentBatteryPercent = newPercent
            self.currentDeviceName = newName
            self.isConnected = newConnected
            NotificationCenter.default.post(name: BluetoothTracker.didUpdateNotification, object: self)
        }
        
        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.async(execute: applyUpdate)
        }
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
    
    private func extractBatteryLevels(from device: IOBluetoothDevice, fallbackDevice: IOBluetoothDevice? = nil, into model: inout BluetoothDeviceModel, isMulti: Bool) {
        func getBatteryValue(from dev: IOBluetoothDevice, selectorName: String) -> Int? {
            let sel = Selector((selectorName))
            guard dev.responds(to: sel) else { return nil }
            let imp = dev.method(for: sel)
            let fn = unsafeBitCast(imp, to: IntBatteryGetter.self)
            let val = fn(dev, sel)
            if val > 0 && val <= 100 {
                return val
            }
            return nil
        }
        
        func query(selectorName: String) -> Int? {
            return getBatteryValue(from: device, selectorName: selectorName)
                ?? (fallbackDevice != nil ? getBatteryValue(from: fallbackDevice!, selectorName: selectorName) : nil)
        }
        
        if isMulti {
            model.leftBattery = query(selectorName: "batteryPercentLeft")
            model.rightBattery = query(selectorName: "batteryPercentRight")
            model.caseBattery = query(selectorName: "batteryPercentCase")
            model.combinedBattery = query(selectorName: "batteryPercentCombined")
            model.singleBattery = query(selectorName: "batteryPercentSingle")
        } else {
            let single = query(selectorName: "batteryPercentSingle")
                ?? query(selectorName: "headsetBatteryPercent")
                ?? query(selectorName: "batteryLevel")
                ?? query(selectorName: "batteryPercentCombined")
                ?? query(selectorName: "batteryPercentLeft")
            
            model.singleBattery = single
        }
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
                    let matchByName = prodName != nil && devices[i].name.caseInsensitiveCompare(prodName!) == .orderedSame
                    let matchByAddr = addr != nil && devices[i].address.replacingOccurrences(of: "-", with: ":").caseInsensitiveCompare(addr!.replacingOccurrences(of: "-", with: ":")) == .orderedSame
                    
                    if matchByName || matchByAddr {
                        if let b = batt, b > 0 && b <= 100 {
                            devices[i].singleBattery = b
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
