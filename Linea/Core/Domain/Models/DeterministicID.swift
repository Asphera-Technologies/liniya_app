//
//  DeterministicID.swift
//  Linea
//
//  Identifiers the engines can create without `UUID()`. A plan for a given day
//  must always get the same id: notifications are keyed by it, and a test that
//  runs twice must produce byte-identical output. So ids are derived from what
//  they identify (the day, the task) rather than from randomness.
//

import Foundation

nonisolated enum DeterministicID {
    /// A stable UUID for a string. Not cryptographic — it only needs to be
    /// collision-free for the handful of ids one user creates per day.
    static func uuid(from string: String) -> UUID {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        // Two FNV-1a passes with different offsets fill the 16 bytes.
        for salt in [UInt64(0xcbf2_9ce4_8422_2325), UInt64(0x9e37_79b9_7f4a_7c15)] {
            var hash = salt
            for byte in Array(string.utf8) {
                hash ^= UInt64(byte)
                hash = hash &* 0x1000_0000_01b3
            }
            withUnsafeBytes(of: hash.bigEndian) { bytes.append(contentsOf: $0) }
        }
        // Shape it as a v4-looking UUID so tools do not choke on it.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The id of the plan for a local day.
    static func planID(day: Date, time: TimeContext) -> UUID {
        uuid(from: "plan|\(dayKey(day, time: time))")
    }

    /// The id of the context snapshot captured for a local day.
    static func snapshotID(day: Date, time: TimeContext, capturedAt: Date) -> UUID {
        uuid(from: "snapshot|\(dayKey(day, time: time))|\(Int(capturedAt.timeIntervalSince1970))")
    }

    /// `2026-09-09` in the user's calendar.
    static func dayKey(_ day: Date, time: TimeContext) -> String {
        let components = time.calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
