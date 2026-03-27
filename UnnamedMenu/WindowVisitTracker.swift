import AppKit

final class WindowVisitTracker {
    static let shared = WindowVisitTracker()
    private(set) var history: [pid_t] = []
    private init() {}

    func record(_ pid: pid_t) {
        history.removeAll { $0 == pid }
        history.insert(pid, at: 0)
    }

    /// Returns `pids` ordered by recency: previous app first, current app last.
    /// Apps not in history preserve their relative z-order after history-ranked apps.
    func ordered(_ pids: [pid_t]) -> [pid_t] {
        guard !history.isEmpty else { return pids }
        let pidsSet = Set(pids)
        var result = history.filter { pidsSet.contains($0) }
        let seen = Set(result)
        result += pids.filter { !seen.contains($0) }
        // Move the current app (first in recency = what user is leaving) to the end,
        // so the previous app (last visited before current) comes first.
        if result.count > 1 {
            result.append(result.removeFirst())
        }
        return result
    }
}
