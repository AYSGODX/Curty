import Foundation
import NaturalLanguage

/// Что выбрано в списке «откуда»: определять самим или заданный язык.
enum TranslationSource: Equatable {
    case automatic
    case fixed(String)
}

enum TranslationLanguagePolicy {
    /// Определяем по содержимому, а не по алфавиту. Прежний способ считал
    /// кириллицу против латиницы и потому принимал вьетнамский за английский —
    /// оба на латинице.
    static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // На двух буквах гадать бессмысленно: определитель уверенно ошибается.
        guard trimmed.count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue
    }

    /// Пара, с которой есть смысл идти в переводчик. Совпадающие языки — не
    /// ошибка, а обычное дело: человек вставил русский текст, а перевод стоит
    /// на русский.
    static func pair(source: String?, target: String) -> (from: String, to: String)? {
        guard let source, !source.isEmpty, source != target else { return nil }
        return (source, target)
    }

    /// Пара для предварительной загрузки. Пока текста нет, определять нечего,
    /// а самый частый случай — прочитать чужое на своём языке.
    static func warmupPair(target: String) -> (from: String, to: String) {
        target == "en" ? ("ru", "en") : ("en", target)
    }

    static func title(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code.uppercased()
    }

    /// Список для меню: коды без повторов, по алфавиту на языке интерфейса.
    static func ordered(_ codes: [String]) -> [String] {
        Array(Set(codes)).sorted { title(for: $0) < title(for: $1) }
    }
}

/// Текст перевода живёт в сторе, а не в @State вьюхи: переключение вкладки
/// пересоздаёт вьюху, и набранный абзац пропадал вместе с ней.
@MainActor
final class TranslateStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case translating
        case complete
        case failed(String)
        /// Языки совпали или язык не определился — переводить нечего.
        case nothingToDo(String)
    }

    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var status: Status = .idle
    @Published private(set) var detected: String?
    @Published private(set) var supported: [String] = []
    /// Языковой пакет для текущей пары не загружен. Система всегда спрашивает
    /// разрешения на загрузку, и лучше спросить при заходе во вкладку, чем
    /// посреди набора текста.
    @Published var needsDownload = false
    @Published var isDownloading = false

    @Published var source: TranslationSource {
        didSet {
            guard source != oldValue else { return }
            preferences.translateSourceCode = {
                if case .fixed(let code) = source { return code }
                return ""
            }()
            translatedText = ""
        }
    }

    @Published var target: String {
        didSet {
            guard target != oldValue else { return }
            preferences.translateTargetCode = target
            translatedText = ""
        }
    }

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        let stored = preferences.translateSourceCode
        source = stored.isEmpty ? .automatic : .fixed(stored)
        target = preferences.translateTargetCode
    }

    /// Язык, с которого переводим на самом деле: либо выбранный руками, либо
    /// определённый по тексту.
    var resolvedSource: String? {
        switch source {
        case .automatic: return detected
        case .fixed(let code): return code
        }
    }

    var pair: (from: String, to: String)? {
        TranslationLanguagePolicy.pair(source: resolvedSource, target: target)
    }

    /// Вьюха могла исчезнуть посреди перевода вместе с сессией, и статус
    /// остался бы «переводим» навсегда.
    func resumeIfInterrupted() {
        if status == .translating { status = .idle }
    }

    func loadSupportedLanguages(_ codes: [String]) {
        supported = TranslationLanguagePolicy.ordered(codes)
    }

    func detectLanguage() {
        guard case .automatic = source else {
            detected = nil
            return
        }
        detected = TranslationLanguagePolicy.detect(sourceText)
    }

    func clearResult() {
        translatedText = ""
        detected = nil
        status = .idle
    }

    /// Переводить нечего, и человеку надо сказать почему: это разные случаи —
    /// язык не опознан и язык совпадает с языком перевода.
    func noteNothingToDo() {
        translatedText = ""
        if resolvedSource == nil {
            status = .nothingToDo("Язык не определился — выберите его вручную")
        } else {
            status = .nothingToDo("Текст уже на этом языке")
        }
    }

    func swapLanguages() {
        guard let from = resolvedSource else { return }
        let previousTarget = target
        target = from
        source = .fixed(previousTarget)
        swap(&sourceText, &translatedText)
        status = .idle
    }
}
