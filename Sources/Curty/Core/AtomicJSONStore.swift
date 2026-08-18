import Foundation

/// Общий путь записи для всех файлов с данными пользователя: атомарно,
/// с классом защиты и правами 0600.
///
/// Класс защиты выдаётся только внутри контейнера песочницы. Вне его —
/// например, когда сборку запустили без подписи — запись с ним падает с
/// EPERM, и без отката данные молча теряются. Урок выучен на JSON-сторах,
/// но применён был только к ним: хранилище снимков падало тем же путём,
/// поэтому запись вынесена в одно место.
enum ProtectedFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch let failure as NSError where failure.code == NSFileWriteNoPermissionError {
            try data.write(to: url, options: [.atomic])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

struct AtomicJSONStore<Value: Codable> {
    let url: URL

    struct LoadResult {
        let value: Value
        /// Куда отложен нечитаемый файл. Не nil — значит данные не пропали, а
        /// лежат рядом, и об этом надо сказать пользователю.
        let corruptedBackup: URL?
    }

    /// Повреждённый файл раньше просто подменялся пустым значением, и первая же
    /// правка затирала его насовсем. Теперь он сохраняется под соседним именем:
    /// одна недописанная запись не должна стоить всех заметок.
    func load(default fallback: @autoclosure () -> Value) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return LoadResult(value: fallback(), corruptedBackup: nil)
        }

        do {
            return LoadResult(value: try JSONDecoder().decode(Value.self, from: data), corruptedBackup: nil)
        } catch {
            NSLog("curty: cannot decode \(url.lastPathComponent): \(error.localizedDescription)")
            return LoadResult(value: fallback(), corruptedBackup: setAside())
        }
    }

    func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try ProtectedFileWriter.write(try encoder.encode(value), to: url)
    }

    private func setAside() -> URL? {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let suffix = stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.appendingPathExtension("corrupt-\(suffix)")

        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return backup
        } catch {
            NSLog("curty: cannot set aside \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
