import AppKit

/// Spotify hands out only a link to the cover, never the image itself, so this
/// is the one thing in Curty that reaches the network. It is fenced in: https
/// only, no credentials in the URL, and only hosts the player itself serves art
/// from.
enum ArtworkURLPolicy {
    static let approvedHosts = ["scdn.co"]
    static let maximumBytes = 5 * 1_024 * 1_024

    static func validate(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              approvedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        else { return nil }
        return url
    }
}

@MainActor
final class ArtworkLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private var currentKey: String?
    private var cache: [String: NSImage] = [:]
    private var task: Task<Void, Never>?

    /// Ephemeral: covers stay in memory for the session and nothing about the
    /// request is written to disk, matching how the rest of the media data is
    /// handled.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func load(from text: String) {
        guard let url = ArtworkURLPolicy.validate(text) else {
            clear()
            return
        }

        let key = url.absoluteString
        // The player is polled once a second; only a new cover does any work.
        guard key != currentKey else { return }
        currentKey = key
        task?.cancel()

        if let cached = cache[key] {
            image = cached
            return
        }

        image = nil
        task = Task { [session] in
            guard let data = try? await Self.fetch(url, using: session),
                  let loaded = NSImage(data: data) else {
                // Неудача не должна замораживать обложку до смены трека:
                // сброс ключа даёт следующему опросу попробовать снова.
                if !Task.isCancelled, self.currentKey == key { self.currentKey = nil }
                return
            }
            guard !Task.isCancelled, self.currentKey == key else { return }
            self.store(loaded, for: key)
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        currentKey = nil
        image = nil
    }

    private func store(_ loaded: NSImage, for key: String) {
        if cache.count >= 12 { cache.removeAll() }
        cache[key] = loaded
        image = loaded
    }

    private static func fetch(_ url: URL, using session: URLSession) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count <= ArtworkURLPolicy.maximumBytes else { return nil }
        return data
    }
}
