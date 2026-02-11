import Foundation
import IOKit
import Observation

@Observable
final class AccelerometerService {
    var gravity: CGVector = CGVector(dx: 0, dy: -4)
    private(set) var isAvailable: Bool = false

    private var connection: io_connect_t = 0
    private var timer: Timer?
    private var smoothedX: Double = 0
    private var smoothedY: Double = 0

    private let smoothingFactor: Double = 0.15
    private let gravityMagnitude: Double = 4.0

    init() {
        setupConnection()
    }

    deinit {
        stop()
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func setupConnection() {
        guard let matching = IOServiceMatching("AppleSMC") else {
            isAvailable = false
            return
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            isAvailable = false
            return
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        if result != kIOReturnSuccess {
            isAvailable = false
            return
        }

        // Try a test read to confirm accelerometer is present
        let testRead = readAccelerometerRaw()
        isAvailable = testRead != nil
    }

    func start() {
        guard isAvailable else { return }
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let raw = readAccelerometerRaw() else { return }

        smoothedX = smoothedX * (1.0 - smoothingFactor) + raw.x * smoothingFactor
        smoothedY = smoothedY * (1.0 - smoothingFactor) + raw.y * smoothingFactor

        let gx = smoothedX * gravityMagnitude
        let gy = smoothedY * gravityMagnitude - gravityMagnitude

        gravity = CGVector(dx: gx, dy: gy)
    }

    private func readAccelerometerRaw() -> (x: Double, y: Double)? {
        guard let xData = readSMCKey("MOCA"),
              let yData = readSMCKey("MOCB") else {
            return nil
        }

        guard xData.count >= 2, yData.count >= 2 else { return nil }

        let rawX = Int16(Int(xData[0]) << 8 | Int(xData[1]))
        let rawY = Int16(Int(yData[0]) << 8 | Int(yData[1]))

        return (x: Double(rawX) / 256.0, y: Double(rawY) / 256.0)
    }

    private func readSMCKey(_ key: String) -> [UInt8]? {
        guard connection != 0 else { return nil }

        let keyChars = Array(key.utf8)
        guard keyChars.count == 4 else { return nil }

        // SMC input/output structures — simplified for accelerometer read
        var inputData = [UInt8](repeating: 0, count: 80)
        var outputData = [UInt8](repeating: 0, count: 80)

        // Set key bytes
        inputData[0] = keyChars[0]
        inputData[1] = keyChars[1]
        inputData[2] = keyChars[2]
        inputData[3] = keyChars[3]

        // Command: read key (5)
        inputData[7] = 5

        var outputSize = 80

        let result = IOConnectCallStructMethod(
            connection,
            2,
            &inputData,
            80,
            &outputData,
            &outputSize
        )

        guard result == kIOReturnSuccess else { return nil }

        return Array(outputData[32..<48])
    }
}
