import Foundation

/// Talks to the furwall-stats Cloudflare Worker (see `cloudflare/`). Two
/// operations: GET /totals (called when the donate sheet appears) and
/// POST /click (fired when the user opens a charity's donate page).
///
/// Graceful degradation: any error — network down, timeout, server 5xx,
/// malformed JSON, or `baseURL` empty — leaves `globalTotal` at nil. The
/// donate sheet hides its footer line in that case rather than showing a
/// stale or fake number.
@MainActor
final class RemoteStats: ObservableObject {
    static let shared = RemoteStats()

    /// Cloudflare Worker base URL. Empty string = remote disabled (the donate
    /// sheet behaves as if the worker were unreachable). See `cloudflare/`
    /// for the worker source + deploy notes.
    private let baseURL = "https://api.olliewagner.com/furwall"

    @Published private(set) var globalTotal: Int?

    /// Optimistically bump the global count locally so the UI animates the
    /// roll-up immediately on click — no waiting for the network round trip.
    /// The next `refresh()` reconciles with the authoritative remote count
    /// (KV is eventually consistent up to ~60s, so we'd otherwise show a
    /// stale number for that whole window).
    func optimisticBump() {
        if let current = globalTotal {
            globalTotal = current + 1
        }
    }

    private struct Totals: Decodable { let total: Int }

    func refresh() async {
        guard !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/totals") else {
            globalTotal = nil
            return
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                globalTotal = nil
                return
            }
            let decoded = try JSONDecoder().decode(Totals.self, from: data)
            globalTotal = decoded.total
        } catch {
            globalTotal = nil
        }
    }

    /// Fire-and-forget POST. Failures silently ignored — we don't want a
    /// network hiccup to interrupt the user opening their donate page.
    func reportClick(charityID: String) {
        guard !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/click") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 2
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["org": charityID])
        Task.detached {
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
