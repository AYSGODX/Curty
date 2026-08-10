import AppKit
import SwiftUI
import Translation

struct TranslateView: View {
    private enum Field: Hashable {
        case source
    }

    @ObservedObject var store: TranslateStore
    /// Уводим в системные настройки — панель при этом должна закрыться, иначе
    /// она висит поверх открывшегося окна.
    let onHandOff: () -> Void
    @State private var configuration: TranslationSession.Configuration?
    /// Какая пара языков сейчас в сессии. Если та же — сессию не пересоздаём,
    /// а просим повторить перевод: пересоздание сбрасывает подготовку пакета.
    @State private var activePair = ""
    @State private var pendingTranslation: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 9) {
            languageBar

            CurtyCard {
                VStack(spacing: 7) {
                    sourceEditor
                    Divider()
                    resultEditor
                }
            }

            statusBar
        }
        .onAppear {
            store.resumeIfInterrupted()
            loadSupportedLanguages()
        }
        // Перевод идёт сам: кнопки «Перевести» нет, набранное переводится через
        // паузу после последнего нажатия.
        .onChange(of: store.sourceText) { _, _ in scheduleTranslation() }
        .onChange(of: store.target) { _, _ in scheduleTranslation(immediately: true) }
        .onChange(of: store.source) { _, _ in scheduleTranslation(immediately: true) }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
    }

    // MARK: - Языки

    /// Оба списка одной ширины, кнопка обмена — фиксированной: иначе она
    /// съезжала при каждой смене языка, потому что названия разной длины.
    private var languageBar: some View {
        HStack(spacing: 6) {
            languageMenu(
                title: sourceTitle,
                isAutomatic: store.source == .automatic,
                includesAutomatic: true
            ) { code in
                store.source = code.map(TranslationSource.fixed) ?? .automatic
            }

            CurtyRowButton(
                systemName: "arrow.left.arrow.right",
                title: "Поменять языки местами",
                size: 26,
                glyphSize: 12,
                isEnabled: store.resolvedSource != nil
            ) {
                withAnimation(.easeOut(duration: 0.16)) { store.swapLanguages() }
            }
            .frame(width: 26)

            languageMenu(
                title: TranslationLanguagePolicy.title(for: store.target),
                isAutomatic: false,
                includesAutomatic: false
            ) { code in
                if let code { store.target = code }
            }
        }
    }

    private var sourceTitle: String {
        switch store.source {
        case .fixed(let code): return TranslationLanguagePolicy.title(for: code)
        case .automatic:
            guard let detected = store.detected else { return "Определить язык" }
            return TranslationLanguagePolicy.title(for: detected)
        }
    }

    private func languageMenu(
        title: String,
        isAutomatic: Bool,
        includesAutomatic: Bool,
        select: @escaping (String?) -> Void
    ) -> some View {
        Menu {
            if includesAutomatic {
                Button("Определить язык") { select(nil) }
                Divider()
            }
            ForEach(store.supported, id: \.self) { code in
                Button(TranslationLanguagePolicy.title(for: code)) { select(code) }
            }
            Divider()
            // Пакеты качаются по требованию, и каждый новый язык спрашивает
            // разрешения посреди работы. Здесь их можно забрать разом и забыть.
            Button("Загрузить языки заранее…") {
                openLanguageSettings()
                onHandOff()
            }
        } label: {
            HStack(spacing: 4) {
                if isAutomatic {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(CurtyTheme.accent)
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .curtyHoverLift(scale: 1.03)
        .help(isAutomatic ? "Язык определяется по тексту" : "Выбрать язык")
    }

    // MARK: - Поля

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

    private var statusBar: some View {
        HStack {
            Label(statusText, systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(1)
            Spacer()
            CurtyRowButton(
                systemName: "doc.on.doc",
                title: "Копировать перевод",
                size: 24,
                glyphSize: 12,
                isEnabled: !store.translatedText.isEmpty,
                confirmsWith: "checkmark"
            ) { copyTranslation() }
        }
    }

    // MARK: - Перевод

    private func loadSupportedLanguages() {
        guard store.supported.isEmpty else { return }
        Task {
            let codes = await LanguageAvailability().supportedLanguages
                .compactMap { $0.languageCode?.identifier }
            store.loadSupportedLanguages(codes)
        }
    }

    /// Пауза перед переводом: иначе каждая буква поднимала бы сессию заново.
    /// Смена языка руками — случай другой, там ждать нечего.
    private func scheduleTranslation(immediately: Bool = false) {
        pendingTranslation?.cancel()

        guard !store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.clearResult()
            return
        }

        pendingTranslation = Task {
            if !immediately {
                try? await Task.sleep(for: .milliseconds(450))
            }
            guard !Task.isCancelled else { return }
            store.detectLanguage()
            startSession()
        }
    }

    private func startSession() {
        guard let pair = store.pair else {
            store.noteNothingToDo()
            return
        }

        let key = "\(pair.from)>\(pair.to)"
        if key == activePair, configuration != nil {
            configuration?.invalidate()
        } else {
            activePair = key
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.from),
                target: Locale.Language(identifier: pair.to)
            )
        }
    }

    private func translate(with session: TranslationSession) async {
        let requested = store.sourceText
        guard !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.status = .translating

        do {
            // Языковой пакет качается по требованию, и до первого перевода его
            // нет ни для одной пары — даже для русско-английской. Система
            // спросит и скачает сама; для уже скачанной пары это ничего не стоит.
            try await session.prepareTranslation()
            let response = try await session.translate(requested)
            // Пока переводили, текст мог смениться — тогда ответ уже не про него.
            guard store.sourceText == requested else { return }
            store.translatedText = response.targetText
            store.status = .complete
        } catch {
            store.status = .failed(error.localizedDescription)
        }
    }

    /// Раздел «Язык и регион»: там системный переводчик держит список языков и
    /// позволяет скачать их впрок.
    private func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyTranslation() {
        guard !store.translatedText.isEmpty else { return }
        InternalPasteboard.write { $0.setString(store.translatedText, forType: .string) }
    }

    private var statusText: String {
        switch store.status {
        case .idle: "Перевод появится сам"
        case .translating: "Переводим…"
        case .complete: "Готово"
        case .failed(let message): message
        case .nothingToDo(let message): message
        }
    }

    private var statusSymbol: String {
        switch store.status {
        case .idle: "character.bubble"
        case .translating: "ellipsis.circle"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .nothingToDo: "info.circle"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .idle: .secondary
        case .translating: CurtyTheme.accent
        case .complete: CurtyTheme.success
        case .failed: .red
        case .nothingToDo: .secondary
        }
    }
}
