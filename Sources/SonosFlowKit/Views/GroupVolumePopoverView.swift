import SwiftUI

public struct GroupVolumePopoverView: View {
    @ObservedObject var coordinator: SonosCoordinator

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Speaker Volumes")
                    .font(.headline)
                Spacer()
                if let group = coordinator.selectedGroup {
                    Text(group.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Master Volume
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Master Group Volume", systemImage: "speaker.wave.3.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(coordinator.volume))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { coordinator.volume },
                        set: { coordinator.setVolume($0) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider()

            // Individual Members
            if let group = coordinator.selectedGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Text("INDIVIDUAL SPEAKERS (\(group.members.count))")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach(group.members) { member in
                        if let ip = member.ip, !ip.isEmpty {
                            MemberVolumeRow(
                                member: member,
                                volume: coordinator.memberVolumes[ip] ?? coordinator.volume,
                                isCoordinator: member.uuid == group.coordinatorUUID,
                                onVolumeChange: { newVol in
                                    coordinator.setMemberVolume(memberIP: ip, volume: newVol)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if let group = coordinator.selectedGroup {
                Task {
                    await coordinator.refreshMemberVolumes(for: group)
                }
            }
        }
    }
}

public struct MemberVolumeRow: View {
    public let member: TopologyMember
    public let volume: Double
    public let isCoordinator: Bool
    public let onVolumeChange: (Double) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(member.roomName)
                        .font(.body.weight(.medium))

                    if isCoordinator {
                        Text("HOST")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text("\(Int(volume))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Slider(
                value: Binding(
                    get: { volume },
                    set: { onVolumeChange($0) }
                ),
                in: 0...100,
                step: 1
            )
            .controlSize(.mini)
        }
    }
}
