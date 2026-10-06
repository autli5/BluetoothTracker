import Foundation
import IOBluetooth
import IOKit
import CoreAudio

func runBluetoothTrackerTests() {
    print("\n--- Running BluetoothTracker Integration Tests ---")
    
    let tracker = BluetoothTracker.shared
    
    // 1. Check device recognition
    TestRunner.assertTrue(tracker.isLikelyHeadphones(name: "HUAWEI FreeBuds 4i", minorClass: 1), "Recognizes HUAWEI FreeBuds 4i as headphones")
    TestRunner.assertTrue(tracker.isLikelyHeadphones(name: "AirPods Pro", minorClass: 1), "Recognizes AirPods Pro as headphones")
    TestRunner.assertTrue(tracker.isLikelyHeadphones(name: "Sony WH-1000XM4", minorClass: 1), "Recognizes Sony WH-1000XM4 as headphones")
    TestRunner.assertEqual(tracker.isLikelyHeadphones(name: "Apple Mouse", minorClass: 3), false, "Rejects Apple Mouse as headphones")
    
    // 2. Scan and verify live device reading
    tracker.updateDeviceList()
    
    print("  [Live Scan Results]")
    for dev in tracker.devices {
        print("    Device: \(dev.name) | Connected: \(dev.isConnected) | Battery: \(dev.primaryBatteryPercent != nil ? "\(dev.primaryBatteryPercent!)%" : "nil")")
    }
    
    if let active = tracker.activeHeadphone {
        print("  Active Headphone detected: \(active.name) (Battery: \(active.primaryBatteryPercent != nil ? "\(active.primaryBatteryPercent!)%" : "nil"))")
        TestRunner.assertTrue(active.isConnected, "Active headphone is connected")
        TestRunner.assertEqual(active.name, "HUAWEI FreeBuds 4i", "Active headphone is HUAWEI FreeBuds 4i")
        TestRunner.assertTrue(active.primaryBatteryPercent != nil, "Active headphone has valid battery percent")
        if let p = active.primaryBatteryPercent {
            TestRunner.assertTrue(p > 0 && p <= 100, "Active headphone battery percent (\(p)%) is between 1 and 100")
        }
    } else {
        print("  No active headphones currently connected.")
    }
    
    // 3. Notification emission test
    var notificationReceived = false
    let observer = NotificationCenter.default.addObserver(
        forName: BluetoothTracker.didUpdateNotification,
        object: nil,
        queue: .main
    ) { _ in
        notificationReceived = true
    }
    
    tracker.updateDeviceList()
    TestRunner.assertTrue(notificationReceived, "BluetoothTracker emits didUpdateNotification on refresh")
    NotificationCenter.default.removeObserver(observer)
}
