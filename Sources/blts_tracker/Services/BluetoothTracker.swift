import Foundation
import IOBluetooth
import IOKit
import CoreAudio
import AudioToolbox

public final class BluetoothTracker: ObservableObject {
    public static let shared = BluetoothTracker()
    
    @Published public var activeHeadphone: BluetoothDeviceModel?
    @Published public var devices: [BluetoothDeviceModel] = []
    
    private var timer: Timer?
    private var lastValidBattery: [String: Int] = [:]
    
    private typealias IntBatteryGetter = @convention(c) (AnyObject, Selector) -> Int
    private typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
    
    private init() {
        setupBluetoothListeners()
        startTracking()
    }
    
    deinit {
        stopTracking()
    }
    
    public func startTracking() {
        stopTracking()
        updateDeviceList()
        
        // Use .common mode so timer runs continuously without pausing
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateDeviceList()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
    
    public func stopTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    public func refreshNow() {
        updateDeviceList()
    }
    
    private func setupBluetoothListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBluetoothChange),
            name: NSNotification.Name("IOBluetoothDeviceWasConnectedNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBluetoothChange),
            name: NSNotification.Name("IOBluetoothDeviceWasDisconnectedNotification"),
            object: nil
        )
    }
    
    @objc private func handleBluetoothChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateDeviceList()
        }
        for delay in [0.2, 0.6, 1.2, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateDeviceList()
            }
        }
    }
    
    public func updateDeviceList() {
        var updatedList: [BluetoothDeviceModel] = []
        let activeAudioName = getActiveCoreAudioDeviceName()
        
        // 1. Scan IOBluetooth paired devices
        if let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in pairedDevices {
                let name = device.nameOrAddress ?? "Unknown Device"
                let address = device.addressString ?? UUID().uuidString
                
                let isAudioOutput = activeAudioName != nil && (
                    name.caseInsensitiveCompare(activeAudioName!) == .orderedSame ||
                    activeAudioName!.localizedCaseInsensitiveContains(name) ||
                    name.localizedCaseInsensitiveContains(activeAudioName!)
                )
                let isConnected = device.isConnected() || isAudioOutput
                
                let majorClass = UInt32(device.deviceClassMajor)
                let minorClass = UInt32(device.deviceClassMinor)
                let isAudio = (majorClass == 4) || isLikelyHeadphones(name: name, minorClass: minorClass) || isAudioOutput
                
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
                    extractBatteryLevels(from: device, into: &model, isMulti: isMulti)
                }
                
                updatedList.append(model)
            }
        }
        
        // 2. IOKit Registry enrich
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
        
        let applyUpdate = { [weak self] in
            guard let self = self else { return }
            self.objectWillChange.send()
            self.devices = updatedList
            self.activeHeadphone = foundActive
        }
        
        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.async(execute: applyUpdate)
        }
    }
    
    private func getActiveCoreAudioDeviceName() -> String? {
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
    
    private func isLikelyHeadphones(name: String, minorClass: UInt32) -> Bool {
        let lower = name.lowercased()
        let keywords = ["buds", "pods", "freebuds", "airpods", "headphone", "headset", "earphone", "earbuds", "wh-", "wf-", "qc", "bose", "sony", "jbl", "beats", "marshall", "sennheiser", "soundcore", "pixel buds", "galaxy buds"]
        for kw in keywords {
            if lower.contains(kw) { return true }
        }
        if minorClass >= 1 && minorClass <= 6 {
            return true
        }
        return false
    }
    
    private func extractBatteryLevels(from device: IOBluetoothDevice, into model: inout BluetoothDeviceModel, isMulti: Bool) {
        func getBatteryValue(selectorName: String) -> Int? {
            let sel = Selector((selectorName))
            guard device.responds(to: sel) else { return nil }
            let imp = device.method(for: sel)
            let fn = unsafeBitCast(imp, to: IntBatteryGetter.self)
            let val = fn(device, sel)
            if val > 0 && val <= 100 {
                return val
            }
            return nil
        }
        
        let addr = model.address
        
        if isMulti {
            model.leftBattery = getBatteryValue(selectorName: "batteryPercentLeft")
            model.rightBattery = getBatteryValue(selectorName: "batteryPercentRight")
            model.caseBattery = getBatteryValue(selectorName: "batteryPercentCase")
            model.combinedBattery = getBatteryValue(selectorName: "batteryPercentCombined")
            model.singleBattery = getBatteryValue(selectorName: "batteryPercentSingle")
        } else {
            let single = getBatteryValue(selectorName: "batteryPercentSingle")
                ?? getBatteryValue(selectorName: "headsetBatteryPercent")
                ?? getBatteryValue(selectorName: "batteryLevel")
                ?? getBatteryValue(selectorName: "batteryPercentCombined")
            
            if let single = single {
                lastValidBattery[addr] = single
                model.singleBattery = single
            } else if let cached = lastValidBattery[addr] {
                model.singleBattery = cached
            }
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
                            if devices[i].singleBattery == nil { devices[i].singleBattery = b }
                        }
                        if devices[i].isMultiBattery {
                            if let bl = battLeft, bl > 0 && bl <= 100 {
                                if devices[i].leftBattery == nil { devices[i].leftBattery = bl }
                            }
                            if let br = battRight, br > 0 && br <= 100 {
                                if devices[i].rightBattery == nil { devices[i].rightBattery = br }
                            }
                            if let bc = battCase, bc > 0 && bc <= 100 {
                                if devices[i].caseBattery == nil { devices[i].caseBattery = bc }
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
