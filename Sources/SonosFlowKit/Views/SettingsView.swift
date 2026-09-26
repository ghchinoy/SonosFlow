import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: SonosCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var pingMessage: String? = nil
    @State private var isPinging: Bool = false
    @State private var cloudPingMessage: String? = nil
    @State private var isCloudPinging: Bool = false
    @State private var isSigningIn: Bool = false
    @State private var cloudToken: CloudToken? = nil
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
                    // Control Engine Picker
                    controlEngineSection

                    Divider()

                    if settings.controlEngine == .local {
                        localEngineSection
                    } else {
                        cloudEngineSection
                    }

                    Divider()

                    // Live Capabilities Inspector
                    capabilitiesSection

                    Divider()

                    // Preferences
                    preferencesSection

                    Divider()

                    // Album Artwork Disk Cache
                    artworkCacheSection

                    Divider()

                    // Diagnostics & Logs
                    diagnosticsSection
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 600)
        .onAppear {
            recentLogs = AppLogger.shared.getRecentLogs(maxLines: 50)
            cloudToken = CloudTokenStorage.shared.loadToken()
            Task {
                await refreshCacheStats()
                if let local = coordinator.backend as? LocalHomectlBackend {
                    isBinaryUpdatedOnDisk = await local.service.client.isBinaryNewerOnDisk()
                }
            }
        }
    }

    // MARK: - Sections

    private var controlEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sonos Control Engine")
                .font(.subheadline.weight(.semibold))

            Picker("Control Engine", selection: Binding(
                get: { settings.controlEngine },
                set: { newEngine in
                    Task {
                        await coordinator.switchEngine(to: newEngine)
                        cloudToken = CloudTokenStorage.shared.loadToken()
                    }
                }
            )) {
                ForEach(ControlEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.controlEngine.subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var localEngineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local homectl MCP Server")
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
    }

    private var cloudEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Official Sonos 27mcp Cloud Account")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                if let token = cloudToken, token.isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed In with Sonos Account")
                            .font(.subheadline.weight(.medium))
                        Text("Client ID: \(token.clientID.prefix(20))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: testCloudConnection) {
                        if isCloudPinging {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isCloudPinging)

                    Button("Sign Out") {
                        CloudTokenStorage.shared.clearToken()
                        cloudToken = nil
                        Task { await coordinator.reloadServer() }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundColor(.orange)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authentication Required")
                            .font(.subheadline.weight(.medium))
                        Text("Sign in with your Sonos credentials in the browser.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: signInWithSonos) {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Sign In with Sonos...")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigningIn)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let ping = cloudPingMessage {
                Text(ping)
                    .font(.caption)
                    .foregroundColor(ping.starts(with: "✅") ? .green : .red)
            }
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active Server Capabilities")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(coordinator.capabilities.rawToolNames.count) Tools Registered")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 6) {
                capabilityRow(title: "Transport & Playback", supported: true, detail: "Play, Pause, Skip, Seek")
                capabilityRow(title: "Volume & Mute Control", supported: coordinator.capabilities.supportsVolumeControl, detail: "Master & Member Slider")
                capabilityRow(title: "Sonos Favorites", supported: coordinator.capabilities.supportsFavorites, detail: "Pinned Household Favorites")
                capabilityRow(title: "Full Playback Queue Management", supported: coordinator.capabilities.supportsQueue, detail: coordinator.capabilities.supportsQueue ? "Direct Q:0 reordering & deletions" : "Unsupported (Single Up Next card)")
                capabilityRow(title: "Direct Audio Stream Player (⌘U)", supported: coordinator.capabilities.supportsAudioStreams, detail: coordinator.capabilities.supportsAudioStreams ? "Local UPnP stream playback" : "Unsupported on official cloud")
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func capabilityRow(title: String, supported: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(supported ? .green : .secondary.opacity(0.6))
                .font(.caption)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(supported ? .primary : .secondary)

            Spacer()

            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var preferencesSection: some View {
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
    }

    private var artworkCacheSection: some View {
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
    }

    private var diagnosticsSection: some View {
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

    // MARK: - Actions

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

    private func signInWithSonos() {
        isSigningIn = true
        cloudPingMessage = nil
        Task {
            let client = CloudMCPClient()
            do {
                let token = try await client.authenticate()
                self.cloudToken = token
                cloudPingMessage = "✅ Successfully authorized with Sonos!"
                await coordinator.reloadServer()
            } catch {
                cloudPingMessage = "❌ Authorization failed: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }

    private func testCloudConnection() {
        isCloudPinging = true
        cloudPingMessage = nil
        Task {
            let client = CloudMCPClient()
            do {
                let (info, tools) = try await client.initialize()
                cloudPingMessage = "✅ Connected to \(info.name) (\(tools.count) tools)"
            } catch {
                cloudPingMessage = "❌ Error: \(error.localizedDescription)"
            }
            isCloudPinging = false
        }
    }
}
