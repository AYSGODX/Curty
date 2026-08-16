import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: AppModel
    /// Выделение множественное: ⌘-клик добавляет и убирает, обычный клик
    /// оставляет один элемент.
    @State private var selection: Set<UUID> = []
    @State private var hoveredID: UUID?
    /// Какую кнопку копирования подсветить галочкой после ⌘C и каким разом:
    /// повторное нажатие по тому же файлу должно подтверждаться заново.
    @State private var copyConfirmation: RowCopyConfirmation?
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // "Добавить" sits on the left because the right-hand slot is where
            // Буфер keeps its "Очистить"; a button that changes meaning when you
            // switch tabs is a button you eventually misclick.
            CurtyStrip {
            HStack(spacing: 8) {
                Button("Добавить", systemImage: "plus") { chooseFiles() }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .curtyHoverLift()

                Text(selection.count > 1
                     ? "Выбрано: \(selection.count)"
                     : "Элементов: \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(CurtyTheme.engravedDim)

                Spacer(minLength: 8)

                if !store.items.isEmpty {
                    Button {
                        model.confirm(
                            "Убрать все файлы с полки?",
                            detail: "Полка забудет ссылки на файлы. Сами файлы останутся на своих местах.",
                            actionTitle: "Убрать"
                        ) { store.clearReferences() }
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
            }

            if store.items.isEmpty {
                DrawnEmptyState(
                    icon: "tray.and.arrow.down",
                    title: "Полка пуста",
                    detail: "Перетащите файлы на вырез экрана\nили добавьте их кнопкой слева."
                )
            } else {
                CurtyListPane(footer: "элементов \(store.items.count)") {
                    LazyVStack(spacing: 5) {
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

        .focusable()
        .focused($isListFocused)
        // Focus is only here so the space bar arrives; the system focus ring
        // around the whole list is just in the way.
        .focusEffectDisabled()
        // Space previews the selected file and closes the preview again, the
        // way it behaves in Finder.
        .onKeyPress(.space) {
            guard let item = selectedItems.first else { return .ignored }
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
            Button("Копировать выделенные файлы") { copySelected() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectedItems.isEmpty)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Шторка закрылась — выделение теряет смысл: фокус ушёл, и при
        // следующем раскрытии подсвеченная строка обещает то, чего нет.
        .onChange(of: model.isPanelOpen) { _, isOpen in
            if !isOpen { selection = [] }
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
        let isSelected = selection.contains(item.id)

        SelectableRow(isSelected: isSelected, isHovered: hoveredID == item.id) {
            HStack(spacing: 9) {
                // Выделение, открытие и перетаскивание висят на этой половине
                // строки, а не на всей: одновременный жест не перебивается
                // кнопкой под курсором, и нажатие на крестик заодно выделяло
                // строку, которую сам же и убирало.
                HStack(spacing: 9) {
                    Image(systemName: rowIcon(for: item))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(rowIconTint(for: item))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CurtyTheme.engraved)
                            .lineLimit(1)
                        if !item.isAvailable {
                            Text("файл сейчас недоступен")
                                .font(.system(size: 10))
                                .foregroundStyle(CurtyTheme.engravedDim)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                // Double click opens, single click only selects — the selection
                // is what the space bar previews.
                .onTapGesture(count: 2) { requestOpen(item) }
                // Selection runs as a simultaneous gesture: as a plain single
                // tap it would have to wait out the double-click interval
                // before it could know it was not the first half of one.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        // Модификатор читаем у системы, а не отдельным жестом:
                        // два жеста на одно нажатие срабатывают непредсказуемо,
                        // какой первым — зависит от версии SwiftUI.
                        if NSEvent.modifierFlags.contains(.command) {
                            if selection.contains(item.id) {
                                selection.remove(item.id)
                            } else {
                                selection.insert(item.id)
                            }
                        } else {
                            selection = [item.id]
                        }
                        isListFocused = true
                    }
                )
                .onDrag {
                    // Выделение не трогаем: перетаскивание одной строки не
                    // должно сбрасывать отмеченные рядом.
                    if !selection.contains(item.id) { selection = [item.id] }
                    // Перетаскивать нечего, пока файл недоступен: пустой
                    // провайдер честнее, чем ссылка в никуда.
                    guard let url = item.url else { return NSItemProvider() }
                    return NSItemProvider(object: url as NSURL)
                }

                rowActions(for: item)
            }
        }
        .opacity(item.isAvailable ? 1 : 0.55)
        .onHover { hovering in
            if hovering { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
        }
    }

    private var selectedItems: [ShelfItem] {
        store.items.filter { selection.contains($0.id) && $0.isAvailable }
    }

    private func copySelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        store.copy(items)
        // Галочка загорается на первой строке выделения: подтверждать нужно
        // сам факт, а мигать всеми строками разом — рябь.
        copyConfirmation = RowCopyConfirmation(items[0].id)
    }

    private func rowIcon(for item: ShelfItem) -> String {
        if !item.isAvailable { return "questionmark.folder" }
        return item.isPotentiallyExecutable ? "exclamationmark.shield" : "doc"
    }

    /// Исполняемый файл помечен красным: в приборе это цвет предупреждения, а
    /// не украшение. Всё остальное — обычная приглушённая гравировка: янтарь
    /// значит «работает сейчас», и раздавать его каждой строке нельзя.
    private func rowIconTint(for item: ShelfItem) -> Color {
        item.isPotentiallyExecutable ? CurtyTheme.danger : CurtyTheme.engravedDim
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
            model.confirm(
                "Открыть исполняемый файл?",
                detail: "«\(item.name)» может запустить код на этом Mac.",
                actionTitle: "Открыть"
            ) {
                if store.open(item, allowingExecutables: true) {
                    model.requestPanelClose()
                }
            }
        } else if store.open(item) {
            model.requestPanelClose()
        }
    }
}
