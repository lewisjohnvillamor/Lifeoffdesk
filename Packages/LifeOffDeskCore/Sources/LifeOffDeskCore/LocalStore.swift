import Foundation

public enum StoreError: Error, Equatable {
    case unsupportedSchema(file: String, found: Int)
}

/// Problems encountered while loading; surfaced to the UI instead of silently discarding data.
public struct StoreIssue: Hashable, Sendable {
    public var file: String
    public var message: String
}

/// Versioned atomic JSON files in one directory. Each write keeps the previous good file
/// as `.bak`; a file that fails to decode falls back to its backup and is set aside, never deleted.
public final class LocalStore: @unchecked Sendable {
    public let directory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    public private(set) var issues: [StoreIssue] = []

    public init(directory: URL) throws {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try fileManager.createDirectory(at: walksDirectory, withIntermediateDirectories: true)
    }

    private var activeSessionURL: URL { directory.appendingPathComponent("active-session.json") }
    private var explorationURL: URL { directory.appendingPathComponent("exploration.json") }
    private var walksDirectory: URL { directory.appendingPathComponent("walks", isDirectory: true) }

    // MARK: Active session

    public func saveActiveSession(_ session: WalkSession) throws {
        try write(session, to: activeSessionURL)
    }

    public func loadActiveSession() -> WalkSession? {
        load(WalkSession.self, from: activeSessionURL, maxSchema: WalkSession.currentSchemaVersion) { $0.schemaVersion }
    }

    public func clearActiveSession() throws {
        try removeWithBackup(activeSessionURL)
    }

    // MARK: Finished walks

    /// Saves the finished walk first, then clears the active file, so a crash in between
    /// leaves a duplicate rather than a lost walk.
    public func commitFinished(_ session: WalkSession) throws {
        try write(session, to: walksDirectory.appendingPathComponent("\(session.id.uuidString).json"))
        try clearActiveSession()
    }

    public func loadFinishedWalks() -> [WalkSession] {
        let urls = (try? fileManager.contentsOfDirectory(at: walksDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { load(WalkSession.self, from: $0, maxSchema: WalkSession.currentSchemaVersion) { $0.schemaVersion } }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Exploration

    public func saveExploration(_ exploration: Exploration) throws {
        try write(exploration, to: explorationURL)
    }

    public func loadExploration() -> Exploration? {
        load(Exploration.self, from: explorationURL, maxSchema: Exploration.currentSchemaVersion) { $0.schemaVersion }
    }

    // MARK: Erase

    /// Removes personal walks and exploration only. Model, catalog and map assets live elsewhere.
    public func erasePersonalData() throws {
        lock.lock(); defer { lock.unlock() }
        for url in [activeSessionURL, explorationURL] {
            for candidate in [url, backupURL(url)] where fileManager.fileExists(atPath: candidate.path) {
                try fileManager.removeItem(at: candidate)
            }
        }
        if fileManager.fileExists(atPath: walksDirectory.path) {
            try fileManager.removeItem(at: walksDirectory)
        }
        let leftovers = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in leftovers where url.lastPathComponent.contains(".corrupt-") {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: walksDirectory, withIntermediateDirectories: true)
        issues.removeAll()
    }

    // MARK: Primitives

    private func backupURL(_ url: URL) -> URL { url.appendingPathExtension("bak") }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        lock.lock(); defer { lock.unlock() }
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp)
        if fileManager.fileExists(atPath: url.path) {
            let backup = backupURL(url)
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            try fileManager.moveItem(at: url, to: backup)
        }
        try fileManager.moveItem(at: temp, to: url)
    }

    private func removeWithBackup(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        for candidate in [url, backupURL(url)] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL, maxSchema: Int, schema: (T) -> Int) -> T? {
        lock.lock(); defer { lock.unlock() }
        let name = url.lastPathComponent
        for candidate in [url, backupURL(url)] {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            do {
                let value = try decoder.decode(T.self, from: data)
                if schema(value) > maxSchema {
                    // Written by a newer app version; keep it untouched.
                    issues.append(StoreIssue(file: name, message: "Saved by a newer app version (schema \(schema(value)))."))
                    return nil
                }
                if candidate != url {
                    issues.append(StoreIssue(file: name, message: "Restored the previous saved copy."))
                }
                return value
            } catch {
                let aside = directory.appendingPathComponent("\(candidate.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))")
                try? fileManager.moveItem(at: candidate, to: aside)
                issues.append(StoreIssue(file: name, message: "A saved file could not be read and was set aside."))
            }
        }
        return nil
    }
}
