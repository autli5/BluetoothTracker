import Foundation
import IOBluetooth

func runProbe() {
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
    for dev in paired where dev.isConnected() {
        let addr = dev.addressString ?? ""
        let sel = Selector(("batteryPercentSingle"))
        if dev.responds(to: sel) {
            let imp = dev.method(for: sel)
            typealias IntFn = @convention(c) (AnyObject, Selector) -> Int
            let fn = unsafeBitCast(imp, to: IntFn.self)
            let val = fn(dev, sel)
            if val > 0 && val <= 100 {
                print("\(addr):\(val)")
                continue
            }
        }
        
        let selPeer = Selector(("peer"))
        if dev.responds(to: selPeer),
           let peer = dev.perform(selPeer)?.takeUnretainedValue() as? NSObject,
           peer.responds(to: sel) {
            let imp = peer.method(for: sel)
            typealias IntFn = @convention(c) (AnyObject, Selector) -> Int
            let fn = unsafeBitCast(imp, to: IntFn.self)
            let val = fn(peer, sel)
            if val > 0 && val <= 100 {
                print("\(addr):\(val)")
            }
        }
    }
}

runProbe()
