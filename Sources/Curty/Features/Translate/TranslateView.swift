import AppKit
import SwiftUI
import Translation

enum TranslationDirection: Equatable {
    case russianToEnglish
    case englishToRussian

    var source: Locale.Language {
        Locale.Language(identifier: self == .russianToEnglish ? "ru" : "en")
    }

    var target: Locale.Language {
        Locale.Language(identifier: self == .russianToEnglish ? "en" : "ru")
    }

    var sourceTitle: String { self == .russianToEnglish ? "Русский" : "Английский" }
    var targetTitle: String { self == .russianToEnglish ? "Английский" : "Русский" }
}

enum TranslationLanguageDetector {
    static func direction(for text: String) -> TranslationDirection? {
        var cyrillicCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
                cyrillicCount += 1
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                latinCount += 1
            default:
                continue
            }
        }

        guard cyrillicCount > 0 || latinCount > 0 else { return nil }
        if cyrillicCount == latinCount { return nil }
        return cyrillicCount > latinCount ? .russianToEnglish : .englishToRussian
    }
}

struct TranslateView: View {
    private enum Status: Equatable {
        case idle
        case translating
        case complete
        case failed(String)
    }

    private enum Field: Hashable {
        case source
    }

    @State private var direction: TranslationDirection = .russianToEnglish
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var status: Status = .idle
    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                languagePill(direction.sourceTitle)
                Spacer()
                Button {
                    swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Поменять языки")
                Spacer()
                languagePill(direction.targetTitle)
            }

            CurtyCard {
                VStack(spacing: 7) {
                    sourceEditor
                    Divider()
                    resultEditor
                }
            }

            HStack {
                Label(statusText, systemImage: statusSymbol)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Spacer()
                Button { copyTranslation() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(translatedText.isEmpty)
                    .help("Копировать перевод")
                    .accessibilityLabel("Копировать перевод")
                Button("Перевести") { requestTranslation() }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .translating)
            }
        }
        .onChange(of: sourceText) { _, newValue in
            applyDetectedLanguage(for: newValue)
        }
        .translationTask(configuration) { session in
            guard status == .translating else { return }
            let requestedText = sourceText
            let requestedDirection = direction
            do {
                let response = try await session.translate(requestedText)
                guard sourceText == requestedText, direction == requestedDirection else { return }
                translatedText = response.targetText
                status = .complete
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private var sourceEditor: some View {
        let isFloating = focusedField == .source || !sourceText.isEmpty
        return ZStack(alignment: .topLeading) {
            TextEditor(text: $sourceText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .source)
                .frame(height: isFloating ? 50 : 62)
                .offset(y: isFloating ? 12 : 0)

            if sourceText.isEmpty {
                Text("Введите или вставьте текст")
                    .font(.system(size: isFloating ? 10 : 13, weight: isFloating ? .medium : .regular))
                    .foregroundStyle(isFloating ? CurtyTheme.accent : Color.secondary.opacity(0.55))
                    .offset(x: 5, y: isFloating ? -1 : 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 62)
        .clipped()
        .animation(.easeOut(duration: 0.18), value: isFloating)
    }

    private var resultEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $translatedText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(height: 62)
                .disabled(true)

            if translatedText.isEmpty {
                Text("Перевод появится здесь")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .offset(x: 5, y: 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 62)
    }

    private func applyDetectedLanguage(for text: String) {
        guard let detected = TranslationLanguageDetector.direction(for: text), detected != direction else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            direction = detected
        }
        translatedText = ""
        configuration = nil
        status = .idle
    }

    private func requestTranslation() {
        applyDetectedLanguage(for: sourceText)
        status = .translating
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: direction.source, target: direction.target)
        } else {
            configuration?.invalidate()
        }
    }

    private func copyTranslation() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    private func swapLanguages() {
        direction = direction == .russianToEnglish ? .englishToRussian : .russianToEnglish
        swap(&sourceText, &translatedText)
        configuration = nil
        status = .idle
    }

    private func languagePill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private var statusText: String {
        switch status {
        case .idle: "Язык определяется автоматически"
        case .translating: "Переводим…"
        case .complete: "Готово"
        case .failed(let message): message
        }
    }

    private var statusSymbol: String {
        switch status {
        case .idle: "character.bubble"
        case .translating: "ellipsis.circle"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: .secondary
        case .translating: CurtyTheme.accent
        case .complete: CurtyTheme.success
        case .failed: .red
        }
    }
}
