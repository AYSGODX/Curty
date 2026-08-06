import Foundation

enum MeetingURLPolicy {
    static let approvedHosts: [String: String] = [
        "meet.google.com": "Google Meet",
        "zoom.us": "Zoom",
        "teams.microsoft.com": "Teams",
        "teams.live.com": "Teams",
        "webex.com": "Webex",
        "whereby.com": "Whereby",
        "meet.jit.si": "Jitsi",
        "telemost.yandex.ru": "Телемост",
    ]

    static func validate(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              approvedHosts.keys.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
        return url
    }

    static func provider(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return approvedHosts.first(where: { host == $0.key || host.hasSuffix(".\($0.key)") })?.value
    }

    static func firstApprovedURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let approved = validate(url) { return approved }
        }
        return nil
    }
}
