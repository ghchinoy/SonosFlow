import SwiftUI
import AppKit
import SonosFlowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinatorReference: SonosCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !window.className.contains("NSStatusBarWindow") {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        guard let coord = coordinatorReference else { return menu }

        // 1. Now Playing item (read-only header)
        if let np = coord.nowPlaying, !np.isStopped {
            let trackItem = NSMenuItem(title: "\(np.displayTitle) — \(np.artist ?? "")", action: nil, keyEquivalent: "")
            trackItem.isEnabled = false
            menu.addItem(trackItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 2. Playback actions
        let isPlaying = coord.nowPlaying?.isPlaying == true
        let playPauseItem = NSMenuItem(
            title: isPlaying ? "Pause" : "Play",
            action: #selector(dockPlayPause),
            keyEquivalent: ""
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(dockNext),
            keyEquivalent: ""
        )
        nextItem.target = self
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(dockPrev),
            keyEquivalent: ""
        )
        prevItem.target = self
        menu.addItem(prevItem)

        // 3. Rooms submenu
        if !coord.groups.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let roomsItem = NSMenuItem(title: "Rooms", action: nil, keyEquivalent: "")
            let roomsSubmenu = NSMenu()
            for group in coord.groups {
                let item = NSMenuItem(
                    title: group.displayName,
                    action: #selector(dockSelectRoom(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = group
                if group.id == coord.selectedGroup?.id {
                    item.state = .on
                }
                roomsSubmenu.addItem(item)
            }
            roomsItem.submenu = roomsSubmenu
            menu.addItem(roomsItem)
        }

        return menu
    }

    @objc private func dockPlayPause() {
        Task { @MainActor in await coordinatorReference?.togglePlayPause() }
    }

    @objc private func dockNext() {
        Task { @MainActor in await coordinatorReference?.next() }
    }

    @objc private func dockPrev() {
        Task { @MainActor in await coordinatorReference?.previous() }
    }

    @objc private func dockSelectRoom(_ sender: NSMenuItem) {
        guard let group = sender.representedObject as? TopologyGroup else { return }
        Task { @MainActor in await coordinatorReference?.selectGroup(group) }
    }
}

@main
struct SonosFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = SonosCoordinator()

    var body: some Scene {
        WindowGroup("SonosFlow") {
            MainSplitView(coordinator: coordinator)
                .onAppear {
                    appDelegate.coordinatorReference = coordinator
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            // Playback Menu
            CommandMenu("Playback") {
                Button(coordinator.nowPlaying?.isPlaying == true ? "Pause" : "Play") {
                    Task { await coordinator.togglePlayPause() }
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Next Track") {
                    Task { await coordinator.next() }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Track") {
                    Task { await coordinator.previous() }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Volume Up") {
                    coordinator.stepVolume(delta: coordinator.settings.volumeDelta)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Volume Down") {
                    coordinator.stepVolume(delta: -coordinator.settings.volumeDelta)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Button(coordinator.isMuted ? "Unmute" : "Mute") {
                    coordinator.toggleMute()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(coordinator.isMiniPlayerMode ? "Exit MiniPlayer" : "MiniPlayer Mode") {
                    coordinator.toggleMiniPlayerMode()
                }
                .keyboardShortcut("m", modifiers: .command)

                Divider()

                Button("Play Audio Stream...") {
                    coordinator.showingStreamPlayer = true
                }
                .keyboardShortcut("u", modifiers: .command)
            }

            // Queue Menu
            CommandMenu("Queue") {
                Button("Refresh Queue") {
                    Task { await coordinator.refreshQueue() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Reload MCP Server") {
                    Task { await coordinator.reloadServer() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Clear Queue...") {
                    coordinator.showingClearQueueConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(coordinator.queueItems.isEmpty)
            }

            // Rooms Menu
            CommandMenu("Rooms") {
                ForEach(Array(coordinator.groups.prefix(9).enumerated()), id: \.element.id) { index, group in
                    Button(action: {
                        Task { await coordinator.selectGroup(group) }
                    }) {
                        HStack {
                            Text(group.displayName)
                            if group.id == coordinator.selectedGroup?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }

                if coordinator.groups.isEmpty {
                    Text("No rooms discovered")
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(settings: coordinator.settings, coordinator: coordinator)
        }

        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            Image(systemName: coordinator.nowPlaying?.isPlaying == true ? "speaker.wave.3.fill" : "hifispeaker")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
