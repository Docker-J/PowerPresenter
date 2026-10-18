import Foundation

public enum MIDICueType: String, Codable, CaseIterable, Sendable {
    case controlChange = "Control Change (CC)"
    case noteOn = "Note On"
    case programChange = "Program Change (PC)"
}

public struct MIDICue: Codable, Sendable, Equatable, Hashable {
    public var type: MIDICueType
    public var channel: UInt8 // 1...16
    public var number: UInt8  // Note (0-127), CC # (0-127), Program # (0-127)
    public var value: UInt8   // Velocity (0-127) or CC Value (0-127)

    public init(
        type: MIDICueType = .controlChange,
        channel: UInt8 = 1,
        number: UInt8 = 20,
        value: UInt8 = 127
    ) {
        self.type = type
        self.channel = max(1, min(16, channel))
        self.number = min(127, number)
        self.value = min(127, value)
    }

    public var displayName: String {
        switch type {
        case .controlChange:
            return "Ch \(channel) • CC #\(number) (Val \(value))"
        case .noteOn:
            return "Ch \(channel) • Note \(number) [\(MIDICue.noteName(for: number))] (Vel \(value))"
        case .programChange:
            return "Ch \(channel) • Program #\(number)"
        }
    }

    public var shortBadgeText: String {
        switch type {
        case .controlChange:
            return "CC \(number)"
        case .noteOn:
            return "Note \(MIDICue.noteName(for: number))"
        case .programChange:
            return "PC \(number)"
        }
    }

    public static func noteName(for note: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (Int(note) / 12) - 1
        let name = names[Int(note) % 12]
        return "\(name)\(octave)"
    }
}
