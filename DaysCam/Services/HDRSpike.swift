import Foundation
import UIKit
import os

/// Spike #587 scaffolding: log file, memory sampler, raw-data side channel.
/// Not for merge.
enum HDRSpike {
    static let isHDRPathOn = UserDefaults.standard.bool(forKey: "spikeHDR")
    static let alternates = UserDefaults.standard.bool(forKey: "spikeAlternate")
    private static var modes: [UUID: Bool] = [:]
    private static var decisions = 0

    /// Decides (once per capture) whether the new path runs: alternates
    /// old/new when `-spikeAlternate 1`, else follows `-spikeHDR`.
    static func decide(for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        decisions += 1
        modes[id] = alternates ? (decisions > 20 || decisions % 2 == 0) : isHDRPathOn
    }
    static func usesHDR(_ id: UUID?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return id.flatMap { modes[$0] } ?? false
    }

    static let useQuality = UserDefaults.standard.bool(forKey: "spikeQuality")
    static let dumpsRaw = UserDefaults.standard.bool(forKey: "spikeRaw")

    private static let lock = NSLock()
    private static var counter = 0
    private static var peakFootprint: UInt64 = 0
    private static var inFlight = 0
    private static var sampler: DispatchSourceTimer?

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func log(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        let url = documents.appendingPathComponent("hdr-spike.log")
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func nextIndex() -> Int {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return counter
    }

    static func dump(_ data: Data, name: String) {
        try? data.write(to: documents.appendingPathComponent(name))
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Starts sampling the footprint every 10 ms while any capture is in flight.
    static func captureBegan() {
        lock.lock(); defer { lock.unlock() }
        if inFlight == 0 {
            peakFootprint = 0
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "hdr-spike.sampler"))
            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.setEventHandler {
                let now = UInt64(footprintMB() * 100)
                lock.lock(); if now > peakFootprint { peakFootprint = now }; lock.unlock()
            }
            timer.resume()
            sampler = timer
        }
        inFlight += 1
    }

    /// Returns the peak footprint (MB) since the first in-flight capture began.
    static func captureEnded() -> Double {
        lock.lock(); defer { lock.unlock() }
        inFlight = max(0, inFlight - 1)
        let peak = Double(peakFootprint) / 100
        if inFlight == 0 { sampler?.cancel(); sampler = nil }
        return peak
    }
}

/// Carries the original photo file data alongside the decoded `UIImage`.
enum HDRSideChannel {
    private static let rawKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private static let outKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func attachRaw(_ data: Data, to image: UIImage) {
        objc_setAssociatedObject(image, rawKey, data, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    static func raw(of image: UIImage) -> Data? { objc_getAssociatedObject(image, rawKey) as? Data }
    static func attachOutput(_ data: Data, to image: UIImage) {
        objc_setAssociatedObject(image, outKey, data, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    static func output(of image: UIImage) -> Data? { objc_getAssociatedObject(image, outKey) as? Data }
}
