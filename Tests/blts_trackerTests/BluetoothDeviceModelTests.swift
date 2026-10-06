import Foundation

public struct TestRunner {
    public static var passed = 0
    public static var failed = 0
    
    public static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
        if actual == expected {
            passed += 1
            print("  ✅ [PASS] \(message)")
        } else {
            failed += 1
            print("  ❌ [FAIL] \(message) -> Expected: \(expected), Got: \(actual) at line \(line)")
        }
    }
    
    public static func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        assertEqual(condition, true, message, file: file, line: line)
    }
}

func runDeviceModelTests() {
    print("\n--- Running BluetoothDeviceModel Tests ---")
    
    // 1. Single Battery Device (like Huawei FreeBuds 4i)
    var singleDevice = BluetoothDeviceModel(
        name: "HUAWEI FreeBuds 4i",
        address: "60-aa-ef-5c-85-07",
        isConnected: true,
        isAudioDevice: true,
        isMultiBattery: false,
        singleBattery: 40
    )
    TestRunner.assertEqual(singleDevice.primaryBatteryPercent, 40, "Single battery device primaryBatteryPercent == 40")
    TestRunner.assertTrue(singleDevice.hasBatteryData, "Single battery device hasBatteryData is true")
    
    // 2. Battery percentage changes from 40 to 30 (Real-time drain simulation)
    singleDevice.singleBattery = 30
    TestRunner.assertEqual(singleDevice.primaryBatteryPercent, 30, "Single battery device updates to 30 on drain")
    
    // 3. Multi Battery Device (Left + Right AirPods / FreeBuds Pro)
    let multiDevice = BluetoothDeviceModel(
        name: "AirPods Pro",
        address: "11-22-33-44-55-66",
        isConnected: true,
        isAudioDevice: true,
        isMultiBattery: true,
        leftBattery: 85,
        rightBattery: 90,
        caseBattery: 100
    )
    TestRunner.assertEqual(multiDevice.primaryBatteryPercent, 85, "Multi battery device picks min(left, right) -> 85")
    
    // 4. Multi Battery with single earbud in ear
    let singleEarbud = BluetoothDeviceModel(
        name: "AirPods Pro",
        address: "11-22-33-44-55-66",
        isConnected: true,
        isAudioDevice: true,
        isMultiBattery: true,
        leftBattery: nil,
        rightBattery: 75
    )
    TestRunner.assertEqual(singleEarbud.primaryBatteryPercent, 75, "Multi battery with only one earbud connected returns 75")
    
    // 5. Zero / Invalid battery handling (disconnected or 0% bug)
    let disconnectedDevice = BluetoothDeviceModel(
        name: "Unknown Headset",
        address: "00-00-00-00-00-00",
        isConnected: false,
        isAudioDevice: true,
        singleBattery: 0
    )
    TestRunner.assertEqual(disconnectedDevice.primaryBatteryPercent, nil, "0% battery is treated as no data / invalid")
}
