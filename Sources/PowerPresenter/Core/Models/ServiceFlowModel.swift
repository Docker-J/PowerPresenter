import Foundation
import SwiftUI

public struct ServiceSection: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var defaultStagePresetID: UUID?
    public var triggerMIDICue: MIDICue?

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder.fill",
        colorHex: String = "#3B82F6",
        defaultStagePresetID: UUID? = nil,
        triggerMIDICue: MIDICue? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.defaultStagePresetID = defaultStagePresetID
        self.triggerMIDICue = triggerMIDICue
    }

    public var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

// Color Hex Helper
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

@MainActor
public final class ServiceFlowManager: ObservableObject {
    public static let shared = ServiceFlowManager()

    @Published public var sections: [ServiceSection] = []

    private let storageKey = "PowerPresenter_ServiceFlowSections"

    private init() {
        loadSections()
    }

    public func loadSections() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ServiceSection].self, from: data),
           !saved.isEmpty {
            self.sections = saved
        } else {
            self.sections = Self.defaultChurchLiturgySections()
            saveSections()
        }
    }

    public func saveSections() {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func addSection(_ section: ServiceSection) {
        sections.append(section)
        saveSections()
    }

    public func updateSection(_ section: ServiceSection) {
        if let idx = sections.firstIndex(where: { $0.id == section.id }) {
            sections[idx] = section
            saveSections()
        }
    }

    public func removeSection(at offsets: IndexSet) {
        sections.remove(atOffsets: offsets)
        saveSections()
    }

    public func moveSection(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        saveSections()
    }

    public func resetToDefaults() {
        self.sections = Self.defaultChurchLiturgySections()
        saveSections()
    }

    public func section(for id: UUID?) -> ServiceSection? {
        guard let id = id else { return nil }
        return sections.first(where: { $0.id == id })
    }

    /// User's requested Church Liturgy:
    /// 카운트다운영상 - 호스팅 - 찬양 - 말씀 - 결단찬양/기도 - 광고
    public static func defaultChurchLiturgySections() -> [ServiceSection] {
        return [
            ServiceSection(
                name: "카운트다운영상",
                iconName: "video.fill",
                colorHex: "#8B5CF6", // Purple
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Standard") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 1)
            ),
            ServiceSection(
                name: "호스팅",
                iconName: "mic.fill",
                colorHex: "#F59E0B", // Amber / Warm Orange
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Standard") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 2)
            ),
            ServiceSection(
                name: "찬양",
                iconName: "music.note",
                colorHex: "#3B82F6", // Bright Blue
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Dual Slides") })?.id
                    ?? StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Named Cue") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 3)
            ),
            ServiceSection(
                name: "말씀",
                iconName: "book.fill",
                colorHex: "#10B981", // Emerald Green
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Speaker Notes") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 4)
            ),
            ServiceSection(
                name: "결단찬양/기도",
                iconName: "hands.sparkles.fill",
                colorHex: "#EC4899", // Rose Pink
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Dual Slides") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 5)
            ),
            ServiceSection(
                name: "광고",
                iconName: "megaphone.fill",
                colorHex: "#06B6D4", // Cyan
                defaultStagePresetID: StageLayoutPreset.defaultPresets.first(where: { $0.name.contains("Standard") })?.id,
                triggerMIDICue: MIDICue(type: .controlChange, channel: 1, number: 20, value: 6)
            )
        ]
    }
}
