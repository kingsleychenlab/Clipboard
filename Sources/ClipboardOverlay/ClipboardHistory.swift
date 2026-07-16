import AppKit
import Foundation

/// The rolling clipboard history: newest first, capped, de-duplicated,
/// and persisted to one JSON file so it survives a relaunch.
final class ClipboardHistory: ObservableObject {
    static let capacity = 100

    /// Images are base64'd into the same JSON file, which inflates them ~33%.
    /// A few full-screen screenshots would otherwise turn a small history into a
    /// multi-hundred-MB file, so oversized images live in memory for the session
    /// but aren't written to disk.
    static let maxPersistedImageBytes = 512 * 1024

    @Published private(set) var items: [ClipItem] = []

    private let storeURL: URL
    private var pendingSave: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "clipboardoverlay.save", qos: .utility)

    static var defaultStoreURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base
            .appendingPathComponent("ClipboardOverlay", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? Self.defaultStoreURL
        load()
    }

    /// Adds a clip. Re-copying something already in the history moves it back to
    /// the top rather than creating a second identical row.
    func add(_ item: ClipItem) {
        if let existing = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            items.remove(at: existing)
        }
        items.insert(item, at: 0)
        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        scheduleSave()
    }

    /// Forgets a clip. Any quit path flushes, so the deletion is durable even if
    /// the app dies before the throttled save fires.
    ///
    /// This only forgets our copy — the system clipboard is left alone. Clearing
    /// it would be a surprise: deleting yesterday's clip shouldn't wipe what
    /// you're holding right now.
    func remove(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([ClipItem].self, from: data)
            items = Array(decoded.prefix(Self.capacity))
            log("history: loaded \(items.count) clip(s) from \(storeURL.path)")
        } catch {
            // A corrupt or outdated file shouldn't take the app down; the
            // history is a convenience, not something worth crashing over.
            log("history: ignoring unreadable store (\(error.localizedDescription))")
        }
    }

    /// Coalesces a burst of copies into one write, at most once per second.
    ///
    /// Deliberately a throttle, not a debounce: re-arming the timer on every add
    /// meant a steady stream of copies kept pushing the write into the future and
    /// nothing was ever saved. Leaving an already-scheduled save alone bounds the
    /// worst case at one second of history.
    private func scheduleSave() {
        guard pendingSave == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Writes immediately and waits for it — used on quit, where an async write
    /// would be killed before it reached the disk.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save(waitUntilDone: true)
    }

    private func save(waitUntilDone: Bool = false) {
        let snapshot = items.filter { item in
            guard item.kind == .image else { return true }
            return (item.imageData?.count ?? 0) <= Self.maxPersistedImageBytes
        }
        let url = storeURL
        let write = { Self.write(snapshot, to: url) }

        // Encoding (and base64'ing images) off the main thread keeps the overlay
        // instant even while a big history is being written.
        waitUntilDone ? saveQueue.sync(execute: write) : saveQueue.async(execute: write)
    }

    private static func write(_ items: [ClipItem], to url: URL) {
        do {
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            // Clip history is sensitive by nature — keep it owner-only.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            log("history: save failed (\(error.localizedDescription))")
        }
    }
}
