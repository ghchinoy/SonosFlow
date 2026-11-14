import Foundation
import AppKit

/// Thread-safe logger for SonosFlow that outputs to stdout and writes to ~/Library/Logs/SonosFlow/sonosflow.log.
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    public let logFileURL: URL
    private let backupLogFileURL: URL
    private let logDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter
    private var isDirectoryCreated = false
    private static let maxLogFileBytes: UInt64 = 5 * 1024 * 1024 // 5 MB

    private init() {
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryDir.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("SonosFlow", isDirectory: true)
        self.logDirectory = logsDir
        self.logFileURL = logsDir.appendingPathComponent("sonosflow.log")
        self.backupLogFileURL = logsDir.appendingPathComponent("sonosflow.log.1")

        self.dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private func ensureDirectoryExistsLocked() {
        if !isDirectoryCreated {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            isDirectoryCreated = true
        }
    }

    private func rotateIfNeededLocked() {
        guard let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= Self.maxLogFileBytes else {
            return
        }
        try? fileManager.removeItem(at: backupLogFileURL)
        try? fileManager.moveItem(at: logFileURL, to: backupLogFileURL)
    }

    public func log(_ message: String, category: String = "APP", level: String = "INFO") {
        lock.lock()
        let timestamp = dateFormatter.string(from: Date())
        let formattedLine = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

        if let data = formattedLine.data(using: .utf8) {
            ensureDirectoryExistsLocked()
            rotateIfNeededLocked()
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? fileHandle.close() }
                    _ = try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
        lock.unlock()

        // Print to standard output outside lock
        print(formattedLine, terminator: "")
    }

    public func error(_ message: String, category: String = "APP") {
        log(message, category: category, level: "ERROR")
    }

    public func warning(_ message: String, category: String = "APP") {
        log(message, category: category, level: "WARN")
    }

    public func mcp(_ message: String) {
        log(message, category: "MCP")
    }

    @MainActor
    public func revealLogInFinder() {
        if fileManager.fileExists(atPath: logFileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logDirectory.path)
        }
    }

    public func getRecentLogs(maxLines: Int = 100) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else {
            return "No logs available."
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let tailBytes: UInt64 = 64 * 1024 // Read at most last 64 KB
        let offset = fileSize > tailBytes ? (fileSize - tailBytes) : 0
        try? handle.seek(toOffset: offset)

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return "No logs available."
        }
        let lines = content.components(separatedBy: .newlines)
        let slice = lines.suffix(maxLines)
        return slice.joined(separator: "\n")
    }
}
