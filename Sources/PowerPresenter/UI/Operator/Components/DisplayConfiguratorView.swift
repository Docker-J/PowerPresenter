import SwiftUI

public struct DisplayConfiguratorView: View {
    @ObservedObject var screens = ScreenCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Output Configurator")
                        .font(.title2.bold())
                    Text("Assign specific connected monitors to Audience Output (Projector) or Stage Display (Confidence Monitor).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            // Multi-Display Clustering Status
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(screens.audienceScreenCount > 0 ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("\(screens.audienceScreenCount) Audience Output\(screens.audienceScreenCount == 1 ? "" : "s")")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(screens.audienceScreenCount > 0 ? 0.15 : 0.05))
                .cornerRadius(6)

                HStack(spacing: 6) {
                    Circle()
                        .fill(screens.stageScreenCount > 0 ? Color.cyan : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("\(screens.stageScreenCount) Stage Display\(screens.stageScreenCount == 1 ? "" : "s")")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(screens.stageScreenCount > 0 ? 0.15 : 0.05))
                .cornerRadius(6)

                Spacer()

                Text("Clustered Multi-Output Active")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }

            // Connected Monitors List
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(screens.displays) { display in
                        DisplayCard(display: display) { selectedRole in
                            screens.assignRole(selectedRole, forScreenIndex: display.id)
                        }
                    }
                }
            }

            Divider()

            // Auxiliary / Preview Window Quick Controls
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Single-Screen Rehearsal Windows")
                        .font(.caption.bold())
                    Text("Open floating test windows directly on your main display:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Toggle Audience Window") {
                    screens.toggleAudienceWindow()
                }
                .buttonStyle(.bordered)

                Button("Toggle Stage Window") {
                    screens.toggleStageWindow()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 580, minHeight: 420)
    }
}

struct DisplayCard: View {
    let display: DisplayDescriptor
    let onRoleChange: (MonitorRole) -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Screen icon with role color
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cardColor.opacity(0.15))
                    .frame(width: 56, height: 44)

                Image(systemName: display.role == .stage ? "person.wave.2.fill" : (display.role == .audience ? "sparkles.tv.fill" : "display"))
                    .font(.title3)
                    .foregroundColor(cardColor)
            }

            // Display Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.headline)
                    if display.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text("Display #\(display.id + 1) • Resolution: \(display.resolution)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Role Picker Dropdown
            Picker("Role", selection: Binding(
                get: { display.role },
                set: { onRoleChange($0) }
            )) {
                ForEach(MonitorRole.allCases) { role in
                    Text(role.rawValue).tag(role)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cardColor.opacity(display.role == .none ? 0.1 : 0.6), lineWidth: 2)
        )
    }

    private var cardColor: Color {
        switch display.role {
        case .none: return .secondary
        case .audience: return .red
        case .stage: return .cyan
        }
    }
}
