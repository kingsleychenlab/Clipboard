import AppKit
import CryptoKit
import Foundation

enum ClipKind: String, Codable {
    case text
    case image
}

/// One entry in the clipboard history. Images are stored as PNG data so the
/// whole history serializes to a single JSON file without side-car assets.
struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipKind
    let text: String?
    let imageData: Data?
    let date: Date

    init(text: String, date: Date = Date()) {
        self.id = UUID()
        self.kind = .text
        self.text = text
        self.imageData = nil
        self.date = date
    }

    init(imageData: Data, date: Date = Date()) {
        self.id = UUID()
        self.kind = .image
        self.text = nil
        self.imageData = imageData
        self.date = date
    }

    /// Identity for de-duplication: two clips with the same fingerprint are the
    /// same content, even though they have different ids and timestamps.
    /// Uses a digest rather than `hashValue` so it stays stable across launches,
    /// which matters once history is restored from disk.
    var fingerprint: String {
        switch kind {
        case .text:
            return "t:" + (text ?? "")
        case .image:
            guard let data = imageData else { return "i:empty" }
            let digest = SHA256.hash(data: data)
            return "i:" + digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Single-line preview for the overlay list and console logging.
    var preview: String {
        switch kind {
        case .text:
            let collapsed = (text ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ")
            return collapsed
        case .image:
            if let data = imageData, let image = NSImage(data: data) {
                let size = image.size
                return "Image \(Int(size.width))×\(Int(size.height))"
            }
            return "Image"
        }
    }

    /// Text the filter matches against.
    var searchText: String {
        switch kind {
        case .text: return text ?? ""
        case .image: return "image"
        }
    }
}
