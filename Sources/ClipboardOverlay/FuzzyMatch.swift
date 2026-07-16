import Foundation

/// Subsequence fuzzy matching: "hw" matches "hello world".
///
/// Scoring favours matches that start at a word boundary and run consecutively,
/// so typing "clip" ranks "clipboard" above "c...l...i...p" scattered across a
/// paragraph. Case-insensitive; an empty needle matches everything.
enum FuzzyMatch {
    static func score(needle: String, haystack: String) -> Int? {
        let needle = needle.lowercased()
        guard !needle.isEmpty else { return 0 }

        let hay = Array(haystack.lowercased())
        let pat = Array(needle)
        guard pat.count <= hay.count else { return nil }

        var score = 0
        var patIndex = 0
        var lastMatch = -1

        for (hayIndex, char) in hay.enumerated() {
            guard patIndex < pat.count, char == pat[patIndex] else { continue }

            if lastMatch == hayIndex - 1 { score += 8 }  // consecutive run
            let isBoundary = hayIndex == 0 || !hay[hayIndex - 1].isLetter && !hay[hayIndex - 1].isNumber
            if isBoundary { score += 6 }
            score += max(0, 4 - hayIndex / 24)  // early matches beat late ones

            lastMatch = hayIndex
            patIndex += 1
        }

        return patIndex == pat.count ? score : nil
    }

    /// Filters newest-first, ranking by score but keeping recency as the
    /// tiebreak — with no query at all, order is pure recency.
    static func filter(_ items: [ClipItem], query: String) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }

        return items
            .enumerated()
            .compactMap { index, item -> (ClipItem, Int, Int)? in
                guard let score = score(needle: trimmed, haystack: item.searchText) else { return nil }
                return (item, score, index)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 > rhs.1
            }
            .map(\.0)
    }
}
