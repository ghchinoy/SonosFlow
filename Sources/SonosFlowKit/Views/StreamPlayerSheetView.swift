import SwiftUI
import AppKit

public struct StreamPlayerSheetView: View {
    @ObservedObject var coordinator: SonosCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var streamURL: String = ""
    @State private var streamTitle: String = ""
    @State private var isPlayingStream: Bool = false

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                    Text("Play Audio Stream")
                        .font(.headline)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Target Room Banner
                    HStack(spacing: 6) {
                        Image(systemName: "hifispeaker")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Target Room: ")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(coordinator.selectedGroup?.displayName ?? "No Room Selected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }

                    // URL Input Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stream URL (HTTP or HTTPS)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("https://stream.example.com/live.mp3", text: $streamURL)
                                .textFieldStyle(.roundedBorder)

                            Button(action: pasteFromClipboard) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .help("Paste from Clipboard")
                        }

                        Text("Optional Display Title")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        TextField("e.g. My Favorite Radio", text: $streamTitle)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Button(action: playCurrentStream) {
                                HStack {
                                    if isPlayingStream {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                    Text("Play in \(coordinator.selectedGroup?.displayName ?? "Room")")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPlayingStream)

                            Button(action: saveAsPreset) {
                                Label("Save Preset", systemImage: "bookmark.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(streamURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 4)
                    }

                    // Custom User Presets (if any)
                    if !coordinator.settings.customPresets.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("MY SAVED PRESETS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(coordinator.settings.customPresets) { preset in
                                HStack(spacing: 12) {
                                    Button(action: { playPreset(preset) }) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.purple.opacity(0.15))
                                                    .frame(width: 34, height: 34)
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.purple)
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(preset.title)
                                                    .font(.body.weight(.medium))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                Text(preset.url)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.accentColor.opacity(0.8))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        coordinator.settings.removeCustomPreset(id: preset.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.caption2)
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove preset")
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider()

                    // Curated Radio Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CURATED RADIO PRESETS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        ForEach(SavedStream.curatedPresets) { preset in
                            Button(action: {
                                playPreset(preset)
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "radio.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.accentColor)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(preset.genre ?? preset.url)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.accentColor.opacity(0.8))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Recent Custom Streams (if any)
                    if !coordinator.settings.recentStreams.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("RECENT STREAMS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(coordinator.settings.recentStreams) { stream in
                                Button(action: {
                                    playPreset(stream)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundColor(.secondary)
                                            .font(.caption)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(stream.title)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(1)
                                            Text(stream.url)
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 520)
        .onAppear {
            autoFillClipboardIfURL()
        }
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if str.hasPrefix("http://") || str.hasPrefix("https://") {
                streamURL = str
            }
        }
    }

    private func autoFillClipboardIfURL() {
        if streamURL.isEmpty, let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if str.hasPrefix("http://") || str.hasPrefix("https://") {
                streamURL = str
            }
        }
    }

    private func saveAsPreset() {
        let cleanURL = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        let cleanTitle = streamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? (URL(string: cleanURL)?.host ?? "Custom Radio") : cleanTitle

        coordinator.settings.addCustomPreset(SavedStream(title: title, url: cleanURL, genre: "Custom Radio"))
    }

    private func playCurrentStream() {
        isPlayingStream = true
        Task {
            await coordinator.playStream(url: streamURL, title: streamTitle.isEmpty ? nil : streamTitle)
            isPlayingStream = false
            dismiss()
        }
    }

    private func playPreset(_ preset: SavedStream) {
        streamURL = preset.url
        streamTitle = preset.title
        playCurrentStream()
    }
}
