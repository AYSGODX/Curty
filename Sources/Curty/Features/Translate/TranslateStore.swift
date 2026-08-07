import Foundation

/// Текст перевода живёт в сторе, а не в @State вьюхи: переключение вкладки
/// пересоздаёт вьюху, и набранный абзац пропадал вместе с ней.
@MainActor
final class TranslateStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case translating
        case complete
        case failed(String)
    }

    @Published var direction: TranslationDirection = .russianToEnglish
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var status: Status = .idle

    /// Вьюха могла исчезнуть посреди перевода вместе с сессией, и статус
    /// остался бы «переводим» навсегда, блокируя кнопку.
    func resumeIfInterrupted() {
        if status == .translating { status = .idle }
    }

    func applyDetectedLanguage(for text: String) -> Bool {
        guard let detected = TranslationLanguageDetector.direction(for: text), detected != direction else {
            return false
        }
        direction = detected
        translatedText = ""
        status = .idle
        return true
    }

    func swapLanguages() {
        direction = direction == .russianToEnglish ? .englishToRussian : .russianToEnglish
        swap(&sourceText, &translatedText)
        status = .idle
    }
}
