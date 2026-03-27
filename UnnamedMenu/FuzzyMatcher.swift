import Foundation

struct FuzzyMatcher {
    /// Returns nil if query is not a subsequence of string; otherwise returns a score
    /// where higher is a better match.
    static func score(query: String, in string: String) -> Double? {
        let q = query.lowercased()
        let s = string.lowercased()
        guard !q.isEmpty else { return 1.0 }

        var qi = q.startIndex
        var si = s.startIndex
        var score = 0.0
        var consecutive = 0
        var prevMatched = false

        while si < s.endIndex && qi < q.endIndex {
            let sc = s[si]
            let qc = q[qi]

            if sc == qc {
                consecutive += 1
                score += Double(consecutive) * 2.0

                if si == s.startIndex {
                    score += 8.0
                } else {
                    let prev = s[s.index(before: si)]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
                        score += 6.0
                    }
                }

                let position = s.distance(from: s.startIndex, to: si)
                score += max(0, 10.0 - Double(position) * 0.5)

                prevMatched = true
                qi = q.index(after: qi)
            } else {
                if prevMatched { consecutive = 0 }
                prevMatched = false
            }

            si = s.index(after: si)
        }

        guard qi == q.endIndex else { return nil }
        return score
    }
}
