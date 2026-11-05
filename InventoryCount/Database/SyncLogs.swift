//  SyncLogs.swift
//  Couchbase Lite's log files, for diagnosing sync on a phone: info level and above, plain text,
//  rotated (at most 6 files of 1 MB per level, so about 20 MB in all), in the app's Caches folder.
//  Model & sync → "Share sync logs" sends them without Xcode.

import Foundation
import CouchbaseLiteSwift

enum SyncLogs {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CouchbaseLiteLogs", isDirectory: true)
    }

    private static var started = false

    /// Turn on file logging, once: at launch, before any other Couchbase Lite call.
    static func start() {
        guard !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LogSinks.file = FileLogSink(level: .info, directory: directory.path, usePlainText: true,
                                    maxKeptFiles: 6, maxFileSize: 1_048_576)
    }

    /// The log files there now, newest first.
    static func files() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "cbllog" || $0.lastPathComponent.hasPrefix("cbl_") }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return a > b
            }
    }
}
