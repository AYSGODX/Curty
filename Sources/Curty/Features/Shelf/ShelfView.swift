import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: AppModel
    @State private var pendingExecutable: ShelfItem?
    @State private var isConfirmingClear = false
    @State private var selectedID: UUID?
    /// Какую кнопку копирования подсветить галочкой после ⌘C и каким разом:
    /// повторное нажатие по тому же файлу должно подтверждаться заново.
    @State private var copyConfirmation: RowCopyConfirmation?
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // "Добавить" sits on the left because the right-hand slot is where
            // Буфер keeps its "Очистить"; a button that changes meaning when you
            // switch tabs is a button you eventually misclick.
            HStack(spacing: 8) {
                Button("Добавить", systemImage: "plus") { chooseFiles() }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .curtyHoverLift()

                Text("Элементов: \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if !store.items.isEmpty {
                    Button {
                        isConfirmingClear = true
                    } label: {
                        Label("Очистить", systemImage: "trash")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(CurtySecondaryButtonStyle())
                    .curtyHoverLift()
                    .help("Убрать все файлы с полки")
                }
            }

            if store.items.isEmpty {
                CurtyCard {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(CurtyTheme.accent)
                        Text("Временная полка файлов")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Добавьте файлы, чтобы держать локальные ссылки под рукой.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 118)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            row(for: item)
                        }
                    }
                }
            }

            if let error = store.lastError {
                CurtyErrorRow(message: error) { store.lastError = nil }
            }
        }
        .confirmationDialog(
            "Открыть исполняемый файл?",
            isPresented: Binding(
                get: { pendingExecutable != nil },
                set: { if !$0 { pendingExecutable = nil } }
            ),
            presenting: pendingExecutable
        ) { item in
            Button("Открыть «\(item.name)»", role: .destructive) {
                if store.open(item, allowingExecutables: true) {
                    model.requestPanelClose()
                }
                pendingExecutable = nil
            }
            Button("Отмена", role: .cancel) { pendingExecutable = nil }
        } message: { item in
            Text("«\(item.name)» может запустить код на этом Mac.")
        }
        .focusable()
        .focused($isListFocused)
        // Focus is only here so the space bar arrives; the system focus ring
        // around the whole list is just in the way.
        .focusEffectDisabled()
        // Space previews the selected file and closes the preview again, the
        // way it behaves in Finder.
        .onKeyPress(.space) {
            guard let item = store.items.first(where: { $0.id == selectedID }) else { return .ignored }
            quickLook(item)
            return .handled
        }
        // ⌘C копирует выделенный файл — то же самое, что кнопка рядом с ним.
        // Сочетание держит именно кнопка, а не onKeyPress: события с Command
        // приходят в окно как key equivalent и до обработчика нажатий не
        // доходят вовсе — клавиша проваливалась в системный сигнал. Кнопка
        // живёт только пока открыта полка, поэтому ⌘C в других вкладках
        // по-прежнему достаётся полям ввода.
        .background {
            Button("Копировать выделенный файл") { copySelected() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectedItem == nil)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Шторка закрылась — выделение теряет смысл: фокус ушёл, и при
        // следующем раскрытии подсвеченная строка обещает то, чего нет.
        .onChange(of: model.isPanelOpen) { _, isOpen in
            if !isOpen { selectedID = nil }
        }
        .confirmationDialog(
            "Убрать все файлы с полки?",
            isPresented: $isConfirmingClear
        ) {
            Button("Убрать", role: .destructive) { store.clearReferences() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Полка забудет ссылки на файлы. Сами файлы останутся на своих местах.")
        }
    }

    /// SwiftUI's fileImporter opens the dialog without bringing the app forward.
    /// Curty runs in the background, so the dialog appeared behind the frontmost
    /// window and the button looked dead. Driving NSOpenPanel directly lets it
    /// be raised and focused.
    private func chooseFiles() {
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = true
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = true
        dialog.prompt = "Добавить"
        dialog.message = "Выберите файлы для полки Curty"

        model.isPresentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { response in
            MainActor.assumeIsolated {
                model.isPresentingDialog = false
                guard response == .OK else { return }
                store.addUserSelectedFiles(dialog.urls)
            }
        }
    }

    /// Недоступная запись остаётся на полке приглушённой: диск подключат
    /// обратно — и она снова заработает. Убрать её может только пользователь.
    @ViewBuilder
    private func row(for item: ShelfItem) -> some View {
        let isSelected = selectedID == item.id

        HStack(spacing: 10) {
            Image(systemName: rowIcon(for: item))
                .foregroundStyle(rowIconTint(for: item))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !item.isAvailable {
                    Text("Файл сейчас недоступен")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
            rowActions(for: item)
        }
        .opacity(item.isAvailable ? 1 : 0.55)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(isSelected ? CurtyTheme.accent.opacity(0.55) : .clear)
        )
        .contentShape(Rectangle())
        // Double click opens, single click only selects — the selection is
        // what the space bar previews.
        .onTapGesture(count: 2) { requestOpen(item) }
        // Selection runs as a simultaneous gesture: as a plain single tap it
        // would have to wait out the double-click interval before it could know
        // it was not the first half of one.
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedID = item.id
                isListFocused = true
            }
        )
        .onDrag {
            selectedID = item.id
            // Перетаскивать нечего, пока файл недоступен: пустой провайдер
            // честнее, чем ссылка в никуда.
            guard let url = item.url else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
    }

    private var selectedItem: ShelfItem? {
        store.items.first { $0.id == selectedID && $0.isAvailable }
    }

    private func copySelected() {
        guard let item = selectedItem else { return }
        store.copy(item)
        copyConfirmation = RowCopyConfirmation(item.id)
    }

    private func rowIcon(for item: ShelfItem) -> String {
        if !item.isAvailable { return "questionmark.folder" }
        return item.isPotentiallyExecutable ? "exclamationmark.shield" : "doc"
    }

    private func rowIconTint(for item: ShelfItem) -> Color {
        if !item.isAvailable { return .secondary }
        return item.isPotentiallyExecutable ? .orange : CurtyTheme.accent
    }

    @ViewBuilder
    private func rowActions(for item: ShelfItem) -> some View {
        HStack(spacing: CurtyTheme.rowActionSpacing) {
            CurtyRowButton(
                systemName: "magnifyingglass",
                title: "Показать в Finder",
                size: CurtyTheme.rowActionSize,
                glyphSize: 13,
                isEnabled: item.isAvailable
            ) { revealInFinder(item) }

            CurtyRowButton(
                systemName: "doc.on.doc",
                title: "Копировать файл (⌘C)",
                size: CurtyTheme.rowActionSize,
                glyphSize: 13,
                isEnabled: item.isAvailable,
                confirmsWith: "checkmark",
                confirmationToken: copyConfirmation?.token(for: item.id)
            ) { store.copy(item) }

            Spacer().frame(width: CurtyTheme.rowActionDestructiveGap)

            CurtyRowButton(
                systemName: "xmark",
                title: "Убрать с полки",
                isDestructive: true,
                size: CurtyTheme.rowActionSize,
                glyphSize: 13
            ) { store.remove(item) }
        }
        .frame(width: CurtyTheme.rowActionClusterWidth, alignment: .trailing)
    }

    private func quickLook(_ item: ShelfItem) {
        guard let url = item.url else { return }
        var isSecurityScoped = false
        if case .securityScopedBookmark = item.location { isSecurityScoped = true }
        QuickLookCoordinator.shared.toggle(url, isSecurityScoped: isSecurityScoped)
    }

    private func rowBackground(for item: ShelfItem) -> Color {
        selectedID == item.id ? CurtyTheme.accent.opacity(0.16) : .primary.opacity(0.045)
    }

    /// Finder comes forward as a result of this, so the panel gets out of the
    /// way instead of hovering over what the user was sent to look at.
    private func revealInFinder(_ item: ShelfItem) {
        store.reveal(item)
        model.requestPanelClose()
    }

    /// Opening hands the file to another app, so the panel steps aside — but
    /// only once the file actually opened, never when the attempt was refused.
    private func requestOpen(_ item: ShelfItem) {
        if item.isPotentiallyExecutable {
            pendingExecutable = item
        } else if store.open(item) {
            model.requestPanelClose()
        }
    }
}
