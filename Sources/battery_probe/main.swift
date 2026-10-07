import Foundation
import IOBluetooth

let isPowerOn = (IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON)
print("POWER:\(isPowerOn ? 1 : 0)")

guard isPowerOn else {
    exit(0)
}

typealias IntFn = @convention(c) (AnyObject, Selector) -> Int

func getInt(_ target: AnyObject, _ selName: String) -> Int? {
    let sel = Selector((selName))
    if target.responds(to: sel) {
        let imp = target.method(for: sel)
        let fn = unsafeBitCast(imp, to: IntFn.self)
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
