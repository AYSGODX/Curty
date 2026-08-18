import AppKit
import SwiftUI

/// Прогрев службы диалогов при запуске.
///
/// В песочнице ПЕРВЫЙ NSOpenPanel() в процессе стоит ~380 мс — за ним
/// поднимается связь с внешней службой диалогов, — а каждый следующий ~140.
/// Прогревочный экземпляр выбрасывается сразу. Держать один живой диалог на
/// всё приложение пробовали — вышло хуже: окно, созданное при запуске,
/// привязывается к пространству рабочего стола, и открытое из полноэкранного
/// приложения утаскивало на рабочий стол, а на самом рабочем столе всплывало
/// под шторкой. Свежий диалог на каждое нажатие рождается в текущем
/// пространстве и поверх всех окон.
@MainActor
enum OpenDialogService {
    static func warmUp() { _ = NSOpenPanel() }
}

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
    /// Строка, до которой выделение схлопнется на отпускании, если нажатие
    /// не переросло в перетаскивание.
    @State private var pendingCollapseID: UUID?

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

                // Сколько всего на полке, написано в подвале списка, и
                // повторять это здесь незачем. Место занимает только то, чего
                // в подвале нет: сколько строк отмечено разом.
                if selection.count > 1 {
                    Text("Выбрано: \(selection.count)")
                        .font(.caption)
                        .foregroundStyle(CurtyTheme.engravedDim)
                }

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
        // Повторное нажатие, пока диалог уже на экране, не должно заводить
        // второй показ того же окна.
        guard !model.isPresentingDialog else { return }
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = true
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = true
        dialog.prompt = "Добавить"
        dialog.message = "Выберите файлы для полки Curty"
        // Диалог обязан оказаться выше шторки при любом исходе гонки: клик по
        // кнопке делает шторку ключевым окном, активация приложения поднимает
        // ключевое окно, и на части машин диалог всплывал под шторкой. Уровни
        // решают порядок без таймингов: шторка на время диалога опускается на
        // обычный этаж, а диалог поднимается на её постоянный.
        // fullScreenAuxiliary — чтобы он показывался и поверх полноэкранных
        // окон, moveToActiveSpace — в текущем пространстве, а не в родном.
        dialog.level = .statusBar
        dialog.collectionBehavior.insert([.fullScreenAuxiliary, .moveToActiveSpace])

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

        SelectableRow(
            isSelected: isSelected,
            isHovered: hoveredID == item.id,
            onPress: { event in press(item, event: event) },
            pressExclusionTrailing: CurtyTheme.rowActionClusterWidth,
            dragSource: {
                // Тащат строку из выделения — едет всё выделение, в порядке
                // полки. Невыделенную — едет она одна: нажатие уже перевело
                // выделение на неё.
                let dragged = selection.contains(item.id)
                    ? store.items.filter { selection.contains($0.id) }
                    : [item]
                return store.beginDrag(dragged)
            },
            onPressEndedWithoutDrag: {
                // Щелчок по строке из выделения схлопывает выделение до неё,
                // как в Finder, — но это известно только на отпускании: на
                // нажатии он неотличим от начала перетаскивания всей пачки.
                guard pendingCollapseID == item.id else { return }
                pendingCollapseID = nil
                selection = [item.id]
            }
        ) {
            HStack(spacing: 9) {
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

                rowActions(for: item)
            }
        }
        .opacity(item.isAvailable ? 1 : 0.55)
        .onHover { hovering in
            if hovering { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
        }
    }

    /// Нажатие в теле строки: выделение, ⌘-выделение и открытие двойным.
    private func press(_ item: ShelfItem, event: NSEvent) {
        // Плита подтверждения перекрывает список только на глаз: нажатия
        // раздаются по прямоугольникам, и без проверки клик по плите заодно
        // выделял бы строку под ней.
        guard model.pendingConfirmation == nil else { return }
        // Счётчик двойного щелчка у macOS растёт по времени, а не по месту:
        // быстрый клик по соседней строке приходит со счётом 2, хотя никакой
        // это не двойной. Замер: нажатие в 43 пунктах от предыдущего через
        // 384 мс — счёт=2. Открытие поэтому требует, чтобы строка уже была
        // выделена первым нажатием той же пары — у настоящего двойного это
        // так, а переклик между файлами остаётся выделением.
        pendingCollapseID = nil
        if event.clickCount >= 2, selection.contains(item.id),
           !event.modifierFlags.contains(.command) {
            requestOpen(item)
        } else if event.modifierFlags.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
            isListFocused = true
        } else if selection.contains(item.id) {
            // Строка уже в выделении — рушить его нельзя: возможно, это
            // начало перетаскивания всей пачки. Схлопывание откладывается до
            // отпускания без перетаскивания.
            pendingCollapseID = item.id
            isListFocused = true
        } else {
            selection = [item.id]
            isListFocused = true
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
