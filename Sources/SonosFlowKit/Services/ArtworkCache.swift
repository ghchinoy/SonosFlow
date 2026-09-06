import Foundation
import AppKit
import SwiftUI
import CryptoKit

/// Two-tier (memory and disk) asynchronous cache for Sonos album artwork.
public actor ArtworkCache {
    public static let shared = ArtworkCache()

    private let memoryCache = NSCache<NSURL, NSImage>()
    public let diskCacheDirectory: URL
    private let fileManager = FileManager.default
    private var inFlightTasks: [URL: Task<NSImage?, Never>] = [:]

    public init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCacheDir = cachesDir.appendingPathComponent("com.sonosflow.app", isDirectory: true)
        let artworkDir = appCacheDir.appendingPathComponent("Artwork", isDirectory: true)
        self.diskCacheDirectory = artworkDir

        try? FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
    }

    /// Computes deterministic file URL on disk for a given artwork URL using SHA-256.
    public func diskFileURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent("\(hash).jpg")
    }

    /// Returns the physical local file URL on disk if cached, downloading it first if needed.
    public func cachedFileURL(for url: URL) async -> URL? {
        let file = diskFileURL(for: url)
        if fileManager.fileExists(atPath: file.path) {
            return file
        }
        // Fetch and cache
        _ = await image(for: url)
        if fileManager.fileExists(atPath: file.path) {
            return file
        }
        return nil
    }

    /// Retrieves image from memory cache, disk cache, or downloads it.
    public func image(for url: URL) async -> NSImage? {
        // 1. Memory Cache
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }

        // 2. Disk Cache
        let file = diskFileURL(for: url)
        if fileManager.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file),
           let img = NSImage(data: data) {
            memoryCache.setObject(img, forKey: url as NSURL)
            return img
        }

        // 3. In-flight Request Coalescing
        if let existingTask = inFlightTasks[url] {
            return await existingTask.value
        }

        let task = Task<NSImage?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return nil
                }
                guard let image = NSImage(data: data) else {
                    return nil
                }

                // Write to disk cache atomically
                try? fileManager.createDirectory(at: self.diskCacheDirectory, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)

                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[url] = task
        let loaded = await task.value
        inFlightTasks.removeValue(forKey: url)

        if let loaded = loaded {
            memoryCache.setObject(loaded, forKey: url as NSURL)
        }
        return loaded
    }

    /// Calculates total disk usage in bytes and number of cached artwork files.
    public func calculateDiskUsage() -> (bytes: Int64, count: Int) {
        guard let files = try? fileManager.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (0, 0)
        }
        var totalBytes: Int64 = 0
        var count = 0
        for file in files where file.pathExtension.lowercased() == "jpg" {
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                totalBytes += Int64(size)
                count += 1
            }
        }
        return (totalBytes, count)
    }

    /// Purges all in-memory and on-disk cached artwork images.
    public func clearAllCache() {
        memoryCache.removeAllObjects()
        if let files = try? fileManager.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// Reveals the disk artwork cache folder in macOS Finder.
    public func revealInFinder() {
        if fileManager.fileExists(atPath: diskCacheDirectory.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: diskCacheDirectory.path)
        }
    }
}

/// SwiftUI View for rendering an album artwork image or fallback SF symbol
public struct ArtworkImageView: View {
    public let url: URL?
    public let size: CGFloat
    public let cornerRadius: CGFloat

    @State private var image: NSImage? = nil

    public init(url: URL?, size: CGFloat, cornerRadius: CGFloat = 8) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.15), Color.secondary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.38))
                            .foregroundColor(.secondary.opacity(0.6))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: url) {
            guard let url = url else {
                image = nil
                return
            }
            image = await ArtworkCache.shared.image(for: url)
        }
    }
}
