import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: SonosCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var pingMessage: String? = nil
    @State private var isPinging: Bool = false
    @State private var recentLogs: String = ""
    @State private var cacheBytes: Int64 = 0
    @State private var cacheCount: Int = 0
    @State private var isBinaryUpdatedOnDisk: Bool = false

    public init(settings: AppSettings, coordinator: SonosCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // MCP Server Binary Path
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sonos MCP Server Binary")
                            .font(.subheadline.weight(.semibold))

                        HStack {
                            TextField("/path/to/homectl/bin/mcp-sonos", text: $settings.mcpBinaryPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse...") {
                                browseForBinary()
                            }

                            Button(action: testConnection) {
                                if isPinging {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Test")
                                }
                            }
                            .disabled(isPinging)

                            Button("Restart") {
                                Task {
                                    await coordinator.reloadServer()
                                    recentLogs = AppLogger.shared.getRecentLogs(maxLines: 50)
                                }
                            }
                            .help("Restart Sonos MCP Server (⌘⇧R)")
                        }

                        Text("Effective Path: \(settings.effectiveMcpBinaryPath)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if isBinaryUpdatedOnDisk {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("New binary build detected on disk. Restart to apply.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        if let ping = pingMessage {
                            Text(ping)
                                .font(.caption)
                                .foregroundColor(ping.starts(with: "✅") ? .green : .red)
                        }
                    }

                    Divider()

                    // Preferences
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Preferences")
                            .font(.subheadline.weight(.semibold))

                        HStack {
                            Text("Polling Interval:")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(settings.pollingInterval)) seconds")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $settings.pollingInterval, in: 2.0...10.0, step: 1.0)
                            .controlSize(.small)

                        HStack {
                            Text("Volume Step Delta:")
                                .font(.subheadline)
                            Spacer()
                            Stepper("\(settings.volumeDelta)%", value: $settings.volumeDelta, in: 1...15)
                        }
                    }

                    Divider()

                    // Album Artwork Disk Cache
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Album Artwork Disk Cache")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Reveal in Finder") {
                                Task {
                                    await ArtworkCache.shared.revealInFinder()
                                }
                            }
                            .font(.caption)

                            Button("Clear Cache") {
                                Task {
                                    await ArtworkCache.shared.clearAllCache()
                                    await refreshCacheStats()
                                }
                            }
                            .font(.caption)
                        }

                        HStack {
                            Text("Storage Used:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formattedByteCount(cacheBytes)) (\(cacheCount) cover\(cacheCount == 1 ? "" : "s"))")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                        }

                        Text("Cached images are stored in ~/Library/Caches/com.sonosflow.app/Artwork/ for offline instant rendering and title bar proxy icon dragging.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Diagnostics & Logs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Diagnostics & Logs")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Reveal Log") {
                                AppLogger.shared.revealLogInFinder()
                            }
                            .font(.caption)

                            Button("Refresh Logs") {
                                recentLogs = AppLogger.shared.getRecentLogs(maxLines: 50)
                            }
                            .font(.caption)
                        }

                        ScrollView {
                            Text(recentLogs.isEmpty ? "No recent logs." : recentLogs)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 120)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 530, height: 530)
        .onAppear {
            recentLogs = AppLogger.shared.getRecentLogs(maxLines: 50)
            Task {
                await refreshCacheStats()
                isBinaryUpdatedOnDisk = await coordinator.sonosService.client.isBinaryNewerOnDisk()
            }
        }
    }

    private func refreshCacheStats() async {
        let stats = await ArtworkCache.shared.calculateDiskUsage()
        self.cacheBytes = stats.bytes
        self.cacheCount = stats.count
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func browseForBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.mcpBinaryPath = url.path
        }
    }

    private func testConnection() {
        isPinging = true
        pingMessage = nil
        Task {
            let path = settings.effectiveMcpBinaryPath
            let client = MCPClient()
            do {
                let (info, tools) = try await client.initializeAndVerify(binaryPath: path)
                await client.stop()
                pingMessage = "✅ Connected to \(info.name) (\(tools.count) tools)"
            } catch {
                pingMessage = "❌ Error: \(error.localizedDescription)"
            }
            isPinging = false
            recentLogs = AppLogger.shared.getRecentLogs(maxLines: 50)
        }
    }
}
