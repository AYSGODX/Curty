import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case media, shelf, clipboard, snippets, calendar, translate, notes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .media: return "Медиа"
            case .shelf: return "Полка"
            case .clipboard: return "Буфер"
            case .snippets: return "Сниппеты"
            case .calendar: return "Календарь"
            case .translate: return "Перевод"
            case .notes: return "Заметки"
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
            }
        }
    }

    @Published var selectedTool: Tool = .media
    @Published var isPanelOpen = false
    @Published var isPinned = false

    let preferences: Preferences
    let clipboard: ClipboardStore
    let shelf: ShelfStore
    let snippets: SnippetStore
    let notes: NoteStore
    let calendar: CalendarStore
    let media: MediaStore

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

        $isPanelOpen
            .removeDuplicates()
            .sink { [weak media] visible in media?.setPanelVisible(visible) }
            .store(in: &cancellables)

        clipboard.onImageSaved = { [weak shelf] url in shelf?.addOwnedFile(url) }
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
    }

    func deleteAllLocalData() {
        clipboard.stopAndClear()
        shelf.clearReferences()
        snippets.clear()
        notes.clear()
        ClipboardVault.clear()
    }
}
