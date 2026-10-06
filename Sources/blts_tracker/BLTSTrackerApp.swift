import SwiftUI
import IOBluetooth
import IOKit
import CoreAudio

@main
struct BLTSTrackerApp: App {
    @ObservedObject var tracker = BluetoothTracker.shared

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            menuBarLabel
        }
    }
    
    @ViewBuilder
    private var menuBarLabel: some View {
        let active = tracker.activeHeadphone
        let isConn = active?.isConnected == true
        let percent = active?.primaryBatteryPercent
        
        if isConn, let p = percent {
            Label(" \(p)%", systemImage: "headphones")
                .labelStyle(.titleAndIcon)
        } else if isConn {
            Label(" ...", systemImage: "headphones")
                .labelStyle(.titleAndIcon)
        } else {
            Label("", systemImage: "headphones")
                .labelStyle(.iconOnly)
        }
    }
    
    @ViewBuilder
    private var menuContent: some View {
        if let dev = tracker.activeHeadphone, dev.isConnected {
            let percentStr = dev.primaryBatteryPercent != nil ? "\(dev.primaryBatteryPercent!)%" : "Определение..."
            Text("🎧 \(dev.name): \(percentStr)")
                .font(.headline)
            
            if let l = dev.leftBattery, let r = dev.rightBattery {
                Text("Левый: \(l)% | Правый: \(r)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("🎧 Наушники не подключены")
                .foregroundColor(.secondary)
        }
        
        Divider()
        
        Button("Обновить заряд") {
            tracker.refreshNow()
        }
        .keyboardShortcut("r")
        
        Divider()
        
        Button("Завершить") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
