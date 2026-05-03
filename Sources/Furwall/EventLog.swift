import Foundation

/// Append-only JSONL log of blocked keystroke events. One line per recorded block.
/// Stored at ~/.furwall/events.jsonl so the user can grep / duckdb / pandas it later.
final class EventLog {
    private let path: URL
    private let queue = DispatchQueue(label: "furwall.eventlog", qos: .utility)
    private let iso = ISO8601DateFormatter()

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".furwall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.path = dir.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
    }

    /// Record a single blocked-burst event. Throttled by the caller — we don't
    /// want one cat-on-keyboard incident producing 200 entries.
    /// `catpurePath` is the absolute path to the snapshot (if one was saved),
    /// or nil. `containsCat` / `containsHuman` come from the post-hoc Vision
    /// classifier (see CatpureClassifier); both nil means "unverified" — older
    /// pre-classifier entries also fall in this bucket.
    func recordBlock(
        at date: Date = Date(),
        catpurePath: String? = nil,
        containsCat: Bool? = nil,
        containsHuman: Bool? = nil
    ) {
        var entry: [String: Any] = [
            "ts": iso.string(from: date),
            "type": "block",
        ]
        if let catpurePath { entry["catpure"] = catpurePath }
        if let containsCat { entry["cat"] = containsCat }
        if let containsHuman { entry["human"] = containsHuman }
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        queue.async { [path] in
            guard let handle = try? FileHandle(forWritingTo: path) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Record a panic-key unlock. Distinct event type so a future review can
    /// distinguish "user mashed Escape" from "cat triggered a block."
    func recordPanic(at date: Date = Date()) {
        let entry: [String: Any] = [
            "ts": iso.string(from: date),
            "type": "panic",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        queue.async { [path] in
            guard let handle = try? FileHandle(forWritingTo: path) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Directory where catpure JPEGs live. Created on init.
    static let catpuresDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".furwall/catpures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Returns a fresh catpure URL like `~/.furwall/catpures/2026-05-02T11-13-16.jpg`.
    static func newCatpureURL(for date: Date = Date()) -> URL {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // Replace `:` in the timestamp so the filename is shell-friendly.
        let stamp = f.string(from: date).replacingOccurrences(of: ":", with: "-")
        return catpuresDir.appendingPathComponent("\(stamp).jpg")
    }

    /// Synchronous count of block entries within the last `days`. Reads the whole
    /// file each time — fine at this volume; revisit if it ever exceeds ~100k lines.
    func recentBlocks(within days: Int) -> Int {
        countBlocks(within: days, where: { _ in true })
    }

    /// Same window but only counts entries the post-hoc classifier confirmed
    /// as cats. Drives the menu's headline stat — verified, not raw. Old
    /// pre-classifier entries lack the `cat` field and are excluded; they age
    /// out naturally as the day window slides forward.
    func recentCatBlocks(within days: Int) -> Int {
        countBlocks(within: days, where: { ($0["cat"] as? Bool) == true })
    }

    /// Scan the log for past entries the classifier did NOT confirm as a cat
    /// and delete the corresponding JPEG if it still exists. Catpures folder
    /// is cat-confirmed only — confirmed humans, "unverified" frames where
    /// Vision missed both species, and pre-classifier entries (no `cat` field
    /// at all) all get cleaned up. Safe to run on every launch — fast,
    /// idempotent (missing files are silently skipped). Returns the number
    /// of JPEGs deleted.
    @discardableResult
    func sweepNonCatCatpures() -> Int {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return 0 }
        var deleted = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let catpurePath = dict["catpure"] as? String else { continue }
            if (dict["cat"] as? Bool) == true { continue }
            if FileManager.default.fileExists(atPath: catpurePath) {
                try? FileManager.default.removeItem(atPath: catpurePath)
                deleted += 1
            }
        }
        return deleted
    }

    private func countBlocks(within days: Int, where predicate: ([String: Any]) -> Bool) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return 0 }
        var count = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = dict["ts"] as? String,
                  let date = iso.date(from: ts),
                  date > cutoff,
                  predicate(dict) else { continue }
            count += 1
        }
        return count
    }
}
