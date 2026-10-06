import Foundation

@main
struct TestMain {
    static func main() {
        print("========================================")
        print("🚀 RUNNING BLTS TRACKER TEST SUITE")
        print("========================================")

        runDeviceModelTests()
        runBluetoothTrackerTests()

        print("\n========================================")
        print("🏁 TEST SUMMARY")
        print("========================================")
        print("Passed: \(TestRunner.passed)")
        print("Failed: \(TestRunner.failed)")

        if TestRunner.failed > 0 {
            print("❌ Some tests failed!")
            exit(1)
        } else {
            print("🎉 ALL TESTS PASSED SUCCESSFULLY!")
            exit(0)
        }
    }
}
