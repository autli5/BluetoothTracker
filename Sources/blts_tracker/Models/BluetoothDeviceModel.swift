import Foundation

public struct BluetoothDeviceModel: Identifiable, Hashable {
    public var id: String { address }
    public let name: String
    public let address: String
    public var isConnected: Bool
    public var isAudioDevice: Bool
    public var isMultiBattery: Bool
    public var majorClass: UInt32
    public var minorClass: UInt32
    
    // Battery properties
    public var singleBattery: Int?      // 1-100 or nil
    public var leftBattery: Int?        // 1-100 or nil
    public var rightBattery: Int?       // 1-100 or nil
    public var caseBattery: Int?        // 1-100 or nil
    public var combinedBattery: Int?    // 1-100 or nil
    
    public var lastUpdated: Date
    
    public init(
        name: String,
        address: String,
        isConnected: Bool = false,
        isAudioDevice: Bool = true,
        isMultiBattery: Bool = false,
        majorClass: UInt32 = 0,
        minorClass: UInt32 = 0,
        singleBattery: Int? = nil,
        leftBattery: Int? = nil,
        rightBattery: Int? = nil,
        caseBattery: Int? = nil,
        combinedBattery: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.name = name
        self.address = address
        self.isConnected = isConnected
        self.isAudioDevice = isAudioDevice
        self.isMultiBattery = isMultiBattery
        self.majorClass = majorClass
        self.minorClass = minorClass
        self.singleBattery = singleBattery
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
        self.combinedBattery = combinedBattery
        self.lastUpdated = lastUpdated
    }
    
    /// Returns best representation of primary battery percentage (> 0)
    public var primaryBatteryPercent: Int? {
        if isMultiBattery {
            if let l = leftBattery, let r = rightBattery, l > 0, r > 0 {
                return min(l, r)
            }
            if let l = leftBattery, l > 0, l <= 100 { return l }
            if let r = rightBattery, r > 0, r <= 100 { return r }
            if let c = combinedBattery, c > 0, c <= 100 { return c }
            if let s = singleBattery, s > 0, s <= 100 { return s }
        } else {
            if let s = singleBattery, s > 0, s <= 100 { return s }
            if let c = combinedBattery, c > 0, c <= 100 { return c }
            if let l = leftBattery, l > 0, l <= 100 { return l }
            if let r = rightBattery, r > 0, r <= 100 { return r }
        }
        return nil
    }
    
    public var hasBatteryData: Bool {
        return primaryBatteryPercent != nil
    }
}
