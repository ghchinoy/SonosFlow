import Foundation
import AppKit

/// Thread-safe logger for SonosFlow that outputs to stdout and writes to ~/Library/Logs/SonosFlow/sonosflow.log.
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    public let logFileURL: URL
    private let logDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter
    private var isDirectoryCreated = false

    private init() {
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryDir.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("SonosFlow", isDirectory: true)
        self.logDirectory = logsDir
        self.logFileURL = logsDir.appendingPathComponent("sonosflow.log")

        self.dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private func ensureDirectoryExistsLocked() {
        if !isDirectoryCreated {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            isDirectoryCreated = true
        }
    }

    public func log(_ message: String, category: String = "APP", level: String = "INFO") {
        let timestamp = dateFormatter.string(from: Date())
        let formattedLine = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

        // Print to standard output
        print(formattedLine, terminator: "")

        // Append to persistent log file
        lock.lock()
        defer { lock.unlock() }

        if let data = formattedLine.data(using: .utf8) {
            ensureDirectoryExistsLocked()
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

        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return "No logs available."
        }
        let lines = content.components(separatedBy: .newlines)
        let slice = lines.suffix(maxLines)
        return slice.joined(separator: "\n")
    }
}
