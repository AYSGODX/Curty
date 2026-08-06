import Foundation

struct AtomicJSONStore<Value: Codable> {
    let url: URL

    func load(default fallback: @autoclosure () -> Value) -> Value {
        guard let data = try? Data(contentsOf: url) else { return fallback() }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            NSLog("curty: cannot decode \(url.lastPathComponent): \(error.localizedDescription)")
            return fallback()
        }
    }

    func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
