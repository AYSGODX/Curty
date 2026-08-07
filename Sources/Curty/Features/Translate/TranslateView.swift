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
    private enum Field: Hashable {
        case source
    }

    @ObservedObject var store: TranslateStore
    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                languagePill(store.direction.sourceTitle)
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
                languagePill(store.direction.targetTitle)
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
                    .disabled(store.translatedText.isEmpty)
                    .help("Копировать перевод")
                    .accessibilityLabel("Копировать перевод")
                Button("Перевести") { requestTranslation() }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .disabled(store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.status == .translating)
            }
        }
        .onAppear { store.resumeIfInterrupted() }
        .onChange(of: store.sourceText) { _, newValue in
            applyDetectedLanguage(for: newValue)
        }
        .translationTask(configuration) { session in
            guard store.status == .translating else { return }
            let requestedText = store.sourceText
            let requestedDirection = store.direction
            do {
                let response = try await session.translate(requestedText)
                guard store.sourceText == requestedText, store.direction == requestedDirection else { return }
                store.translatedText = response.targetText
                store.status = .complete
            } catch {
                store.status = .failed(error.localizedDescription)
            }
        }
    }

    private var sourceEditor: some View {
        let isFloating = focusedField == .source || !store.sourceText.isEmpty
        return ZStack(alignment: .topLeading) {
            TextEditor(text: $store.sourceText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .source)
                .frame(height: isFloating ? 50 : 62)
                .offset(y: isFloating ? 12 : 0)

            if store.sourceText.isEmpty {
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
            TextEditor(text: $store.translatedText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(height: 62)
                .disabled(true)

            if store.translatedText.isEmpty {
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
        var changed = false
        withAnimation(.easeOut(duration: 0.16)) {
            changed = store.applyDetectedLanguage(for: text)
        }
        if changed { configuration = nil }
    }

    private func requestTranslation() {
        applyDetectedLanguage(for: store.sourceText)
        store.status = .translating
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: store.direction.source, target: store.direction.target)
        } else {
            configuration?.invalidate()
        }
    }

    private func copyTranslation() {
        guard !store.translatedText.isEmpty else { return }
        InternalPasteboard.write { $0.setString(store.translatedText, forType: .string) }
    }

    private func swapLanguages() {
        store.swapLanguages()
        configuration = nil
    }

    private func languagePill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private var statusText: String {
        switch store.status {
        case .idle: "Язык определяется автоматически"
        case .translating: "Переводим…"
        case .complete: "Готово"
        case .failed(let message): message
        }
    }

    private var statusSymbol: String {
        switch store.status {
        case .idle: "character.bubble"
        case .translating: "ellipsis.circle"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .idle: .secondary
        case .translating: CurtyTheme.accent
        case .complete: CurtyTheme.success
        case .failed: .red
        }
    }
}
