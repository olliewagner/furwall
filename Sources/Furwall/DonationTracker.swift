import Foundation
import Combine

/// Local-only, anonymous click counter for donate-page visits. Persists to
/// UserDefaults under one key. We can't observe actual donation amounts
/// (Furwall is a deep-link referrer, not a payment intermediary), so the
/// only thing we can honestly count is "user opened a donate page."
///
/// Display copy elsewhere should say "donation pages opened," not "$ raised"
/// — to claim the latter, we'd need a backend with self-reported amounts.
@MainActor
final class DonationTracker: ObservableObject {
    static let shared = DonationTracker()

    private let key = "furwall.donate.clickCounts.v1"
    private let defaults = UserDefaults.standard

    /// Per-charity click counts, keyed by `Charity.id`.
    @Published private(set) var counts: [String: Int]

    var total: Int { counts.values.reduce(0, +) }

    init() {
        if let raw = defaults.dictionary(forKey: key) as? [String: Int] {
            counts = raw
        } else {
            counts = [:]
        }
    }

    func recordClick(for charity: Charity) {
        counts[charity.id, default: 0] += 1
        defaults.set(counts, forKey: key)
    }

    func count(for charity: Charity) -> Int {
        counts[charity.id, default: 0]
    }
}
