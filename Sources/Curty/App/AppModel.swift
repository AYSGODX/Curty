import AppKit
import Combine

/// The stored order is user data, so it can be stale, truncated, or name a tool
/// that no longer exists. Keep whatever is still valid in the stored order and
/// append the rest, so a tool added in a later version can never go missing.
enum ToolOrderPolicy {
    static func resolve(stored: [String], available: [AppModel.Tool]) -> [AppModel.Tool] {
        var placed: Set<AppModel.Tool> = []
        var ordered: [AppModel.Tool] = []

        for raw in stored {
            guard let tool = AppModel.Tool(rawValue: raw),
                  available.contains(tool),
                  !placed.contains(tool) else { continue }
            placed.insert(tool)
            ordered.append(tool)
        }

        ordered.append(contentsOf: available.filter { !placed.contains($0) })
        return ordered
    }

    static func move(_ tool: AppModel.Tool, toIndex index: Int, in order: [AppModel.Tool]) -> [AppModel.Tool] {
        guard let from = order.firstIndex(of: tool) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(tool, at: min(max(0, index), result.count))
        return result
    }
}

/// Какие разделы рельса спрятаны и куда уходит выбор, когда прячут активный.
enum RailVisibilityPolicy {
    /// Настройки спрятать нельзя: это дверь обратно к самому переключателю.
    /// Незнакомые значения из хранилища молча отбрасываются.
    static func resolve(stored: [String]) -> Set<AppModel.Tool> {
        Set(stored.compactMap(AppModel.Tool.init(rawValue:)).filter { $0 != .settings })
    }

    /// Выбранным может оставаться только то, что видно (настройки видны
    /// всегда). Спрятали активный раздел — выбор уходит на первый видимый,
    /// а спрятали всё — на настройки.
    static func selection(current: AppModel.Tool, visible: [AppModel.Tool]) -> AppModel.Tool {
        if current == .settings || visible.contains(current) { return current }
        return visible.first ?? .settings
    }
}

/// Вопрос, заданный перед разрушающим действием.
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let actionTitle: String
    let perform: () -> Void
}

@MainActor
final class AppModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case media, shelf, clipboard, snippets, calendar, translate, notes, settings

        var id: String { rawValue }

        /// Settings sit apart at the foot of the rail, so they are not part of
        /// the tool list itself.
        static var primary: [Tool] { allCases.filter { $0 != .settings } }

        var title: String {
            switch self {
            case .media: return "Медиа"
            case .shelf: return "Полка"
            case .clipboard: return "Буфер"
            case .snippets: return "Сниппеты"
            case .calendar: return "Календарь"
            case .translate: return "Перевод"
            case .notes: return "Заметки"
            case .settings: return "Настройки"
            }
        }

        var symbol: String {
            switch self {
            case .media: return "music.note"
            case .shelf: return "tray.full"
            case .clipboard: return "doc.on.clipboard"
            case .snippets: return "sparkles.rectangle.stack"
            case .calendar: return "calendar"
            case .translate: return "character.bubble"
            case .notes: return "square.and.pencil"
            case .settings: return "gearshape"
            }
        }
    }

    @Published var selectedTool: Tool = .media
    @Published var isPanelOpen = false
    @Published var isPinned = false
    /// Set while a system dialog is up, so the panel neither slides away the
    /// moment the pointer leaves it nor covers the dialog it opened.
    @Published var isPresentingDialog = false {
        didSet {
            guard isPresentingDialog != oldValue else { return }
            onDialogPresentationChange?(isPresentingDialog)
        }
    }

    /// Своё модальное окно поверх панели — например, редактор сниппета. В
    /// отличие от системного диалога уровень окна ему понижать не нужно: оно
    /// и так принадлежит нам, а понижение увело бы панель за чужие окна.
    @Published var isPresentingEditor = false

    /// Открыто выпадающее меню — список языков, часовых поясов. Оно рисуется
    /// поверх панели и выходит за её границы, так что при выборе курсор
    /// оказывается снаружи: панель уезжала, а меню оставалось висеть.
    @Published var isPresentingMenu = false

    /// Заданный вопрос о разрушающем действии. Живёт в модели, а не в
    /// экране: плита должна гасить всю панель целиком, включая рельс и
    /// заголовок, — накрыв одну лишь область содержимого, она оставляла по
    /// краям светлую рамку и читалась как сбой вёрстки.
    @Published var pendingConfirmation: PendingConfirmation?

    func confirm(
        _ title: String,
        detail: String,
        actionTitle: String,
        perform: @escaping () -> Void
    ) {
        pendingConfirmation = PendingConfirmation(
            title: title, detail: detail, actionTitle: actionTitle, perform: perform
        )
    }

    /// Сколько сверху съедает вырез экрана. Корпус панели нарочно заходит под
    /// него, чтобы выглядеть подвешенным к самому вырезу, — но содержимое туда
    /// заезжать не должно: заголовок раздела попадал прямо в вырез и пропадал.
    /// На маках без выреза остаётся нулём.
    @Published var notchInset: CGFloat = 0

    /// Панель остаётся на экране, даже если курсор ушёл. Проверка была
    /// размазана по трём местам, и добавить к ней четвёртую причину значило
    /// не забыть про каждое.
    var keepsPanelOpen: Bool {
        isPinned || isPresentingDialog || isPresentingEditor || isPresentingMenu
            || pendingConfirmation != nil || isEditingRailSections
    }

    /// Wired by the panel controller, which owns the window itself.
    var onDialogPresentationChange: ((Bool) -> Void)?
    var onCloseRequest: (() -> Void)?

    /// Used by actions that hand the user over to another app, where leaving
    /// the panel hanging over the result would only be in the way.
    func requestPanelClose() { onCloseRequest?() }
    @Published private(set) var orderedTools: [Tool] = Tool.primary
    @Published private(set) var hiddenTools: Set<Tool> = []
    /// Плита «Изменить разделы» поверх панели.
    @Published var isEditingRailSections = false

    /// Рельс в порядке пользователя и без спрятанного. Настройки живут вне
    /// этого списка — они пришиты к низу рельса.
    var visibleTools: [Tool] { orderedTools.filter { !hiddenTools.contains($0) } }

    let preferences: Preferences
    let clipboard: ClipboardStore
    let shelf: ShelfStore
    let snippets: SnippetStore
    let notes: NoteStore
    let calendar: CalendarStore
    let media: MediaStore
    let updates: UpdateChecker
    let translate: TranslateStore

    private var cancellables = Set<AnyCancellable>()

    init() {
        let preferences = Preferences()
        self.preferences = preferences
        clipboard = ClipboardStore()
        shelf = ShelfStore()
        snippets = SnippetStore()
        notes = NoteStore()
        calendar = CalendarStore()
        media = MediaStore()
        updates = UpdateChecker()
        translate = TranslateStore(preferences: preferences)

        preferences.$clipboardMonitoringEnabled
            .removeDuplicates()
            .sink { [weak clipboard] enabled in
                if enabled { clipboard?.start() } else { clipboard?.stopAndClear() }
            }
            .store(in: &cancellables)

        preferences.$clipboardImagesEnabled
            .removeDuplicates()
            .sink { [weak clipboard] enabled in clipboard?.capturesImages = enabled }
            .store(in: &cancellables)

        preferences.$mediaIntegrationEnabled
            .removeDuplicates()
            .sink { [weak media] enabled in
                if enabled { media?.start() } else { media?.stop() }
            }
            .store(in: &cancellables)

        preferences.$toolOrder
            .removeDuplicates()
            .sink { [weak self] stored in
                self?.orderedTools = ToolOrderPolicy.resolve(stored: stored, available: Tool.primary)
            }
            .store(in: &cancellables)

        preferences.$hiddenTools
            .removeDuplicates()
            .sink { [weak self] stored in
                guard let self else { return }
                hiddenTools = RailVisibilityPolicy.resolve(stored: stored)
                // Спрятанный раздел не может оставаться открытым: панель
                // показывала бы то, чего в рельсе больше нет.
                let corrected = RailVisibilityPolicy.selection(
                    current: selectedTool,
                    visible: visibleTools
                )
                if corrected != selectedTool { select(corrected) }
            }
            .store(in: &cancellables)

        $isPanelOpen
            .removeDuplicates()
            .sink { [weak media] visible in media?.setPanelVisible(visible) }
            .store(in: &cancellables)

        // Раскрытие шторки — единственный момент, когда точно известно, что на
        // список сейчас будут смотреть. Без этого он оставался таким, каким
        // его собрали при переходе на вкладку, хотя с тех пор прошли часы и
        // система успела дотянуть новые события из Google.
        $isPanelOpen
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.calendar.refreshAuthorization() }
            .store(in: &cancellables)

        calendar.$authorization
            .removeDuplicates()
            .filter { $0 == .granted }
            .sink { [weak preferences] _ in preferences?.calendarAccessWasGranted = true }
            .store(in: &cancellables)

        // Текст, оказавшийся в переводчике, вычёркиваем из истории: его
        // копировали как средство, а не как содержимое, которое нужно хранить.
        translate.$sourceText
            .removeDuplicates()
            .sink { [weak clipboard] text in clipboard?.forgetText(text) }
            .store(in: &cancellables)

        clipboard.onImageSaved = { [weak shelf] url in shelf?.addOwnedFile(url) }
        clipboard.onFileSaved = { [weak shelf] url in shelf?.addUserSelectedFiles([url]) ?? false }
        calendar.onPermissionPromptChange = { [weak self] isPresenting in
            self?.isPresentingDialog = isPresenting
        }
    }

    func start() {
        shelf.load()
        snippets.load()
        notes.load()
        if preferences.clipboardMonitoringEnabled { clipboard.start() }
        if preferences.mediaIntegrationEnabled { media.start() }
    }

    func stop() {
        clipboard.stopAndClear()
        media.stop()
        notes.flush()
    }

    func select(_ tool: Tool) {
        selectedTool = tool
        if tool == .calendar { calendar.refreshAuthorization() }
        if tool == .settings { updates.checkIfStale() }
    }

    func moveTool(_ tool: Tool, toIndex index: Int) {
        let moved = ToolOrderPolicy.move(tool, toIndex: index, in: orderedTools)
        guard moved != orderedTools else { return }
        preferences.toolOrder = moved.map(\.rawValue)
    }

    /// Перестановка по месту на экране: спрятанные разделы в рельсе не
    /// участвуют, поэтому цель — видимый сосед, а двигаем в полном списке.
    func moveTool(_ tool: Tool, toVisibleIndex index: Int) {
        let visible = visibleTools
        guard let currentIndex = visible.firstIndex(of: tool) else { return }
        let target = min(max(0, index), visible.count - 1)
        guard target != currentIndex else { return }
        guard let fullIndex = orderedTools.firstIndex(of: visible[target]) else { return }
        moveTool(tool, toIndex: fullIndex)
    }

    func setTool(_ tool: Tool, hidden: Bool) {
        guard tool != .settings else { return }
        var stored = Set(preferences.hiddenTools)
        if hidden { stored.insert(tool.rawValue) } else { stored.remove(tool.rawValue) }
        preferences.hiddenTools = stored.sorted()
    }

    /// Сброс левой панели целиком: и порядок, и видимость.
    func resetRailSettings() {
        preferences.toolOrder = []
        preferences.hiddenTools = []
    }

    func deleteAllLocalData() {
        // clear, а не stopAndClear: удаление данных не должно втихую выключать
        // наблюдение, оставляя тумблер в положении «включено».
        clipboard.clear()
        shelf.clearReferences()
        snippets.clear()
        notes.clear()
        ClipboardVault.clear()
    }
}
