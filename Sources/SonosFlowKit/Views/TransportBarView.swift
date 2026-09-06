import SwiftUI

public struct TransportBarView: View {
    @ObservedObject var coordinator: SonosCoordinator
    @State private var showingGroupVolumes: Bool = false

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Mute / Speaker Icon Button
            Button(action: {
                coordinator.toggleMute()
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14))
                    .foregroundColor(coordinator.isMuted ? .red : .secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(coordinator.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(coordinator.isMuted ? "Unmute master volume" : "Mute master volume")

            // Step Down Button
            Button(action: {
                coordinator.stepVolume(delta: -coordinator.settings.volumeDelta)
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Volume Down 5% (⌘↓)")
            .accessibilityLabel("Decrease volume 5 percent")

            // Master Volume Slider
            Slider(
                value: Binding(
                    get: { coordinator.volume },
                    set: { newVol in coordinator.setVolume(newVol) }
                ),
                in: 0...100,
                step: 1
            )
            .controlSize(.small)
            .frame(maxWidth: 220)
            .accessibilityLabel("Master volume")

            // Step Up Button
            Button(action: {
                coordinator.stepVolume(delta: coordinator.settings.volumeDelta)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Volume Up 5% (⌘↑)")
            .accessibilityLabel("Increase volume 5 percent")

            // Percentage Label
            Text("\(Int(coordinator.volume))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)

            // Individual Speaker Volumes Popover for Stereo Pairs & Groups
            if (coordinator.selectedGroup?.members.count ?? 0) > 1 {
                Button(action: { showingGroupVolumes.toggle() }) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 12))
                        .foregroundColor(showingGroupVolumes ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Adjust individual speaker volumes in group")
                .accessibilityLabel("Individual speaker volumes")
                .popover(isPresented: $showingGroupVolumes, arrowEdge: .bottom) {
                    GroupVolumePopoverView(coordinator: coordinator)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var volumeIcon: String {
        if coordinator.isMuted || coordinator.volume == 0 {
            return "speaker.slash.fill"
        } else if coordinator.volume < 33 {
            return "speaker.wave.1.fill"
        } else if coordinator.volume < 66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
