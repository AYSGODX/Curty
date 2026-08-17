import Foundation

struct ScratchNote: Identifiable, Codable, Equatable {
    let id: UUID
    /// Заголовок не обязателен. Optional, а не пустая строка, чтобы файлы,
    /// записанные до его появления, читались без миграции.
    var title: String?
    var text: String
    var modifiedAt: Date

    /// Дан ли заметке настоящий заголовок: одни пробелы заголовком не считаются.
    var hasTitle: Bool {
        !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Чем заметка подписана в списке: заголовком, если он дан, иначе — как и
    /// прежде — началом текста; заметка без того и другого названа пустой.
    var listLabel: String {
        if hasTitle {
            return title!.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? "пустая заметка" : text
    }
}

/// Удалённая запись, которую ещё можно вернуть. Подтверждение на каждое
/// удаление быстро надоедает, поэтому здесь окно отмены: промах по строке не
/// стоит написанного руками текста.
struct PendingDeletion<Item>: Equatable where Item: Equatable {
    static var window: Duration { .seconds(4) }

    let item: Item
    let index: Int

    static func == (lhs: PendingDeletion<Item>, rhs: PendingDeletion<Item>) -> Bool {
        lhs.item == rhs.item && lhs.index == rhs.index
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var items: [ScratchNote] = []
    @Published var selectedID: UUID?
    @Published var lastError: String?
    @Published private(set) var pendingDeletion: PendingDeletion<ScratchNote>?

    private let store = AtomicJSONStore<[ScratchNote]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("notes.json")
    )
    private var pendingSave: DispatchWorkItem?
    private var undoWindow: Task<Void, Never>?

    func load() {
        let result = store.load(default: [])
        items = result.value
        selectedID = items.first?.id
        if let backup = result.corruptedBackup {
            lastError = "Файл заметок был повреждён. Прежний сохранён: \(backup.lastPathComponent)"
        }
    }

    func add() {
        let note = ScratchNote(id: UUID(), text: "", modifiedAt: Date())
        items.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    /// Предел длины заметки. История буфера обязана принимать хотя бы столько
    /// же, иначе скопированная целиком заметка в неё не попадает.
    static let maxCharacters = 250_000

    /// С этого места показывается счётчик. Предел срабатывал молча: текст в
    /// поле оставался, а сохранён не был, и человек узнавал об этом только по
    /// красной строке ошибки. Запас в пятьдесят тысяч даёт время заметить.
    static let counterThreshold = 200_000

    func update(_ id: UUID, title: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
        items[index].modifiedAt = Date()
        scheduleSave()
    }

    func update(_ id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        // Проверка идёт на каждое нажатие клавиши, а text.count обходит строку
        // целиком — на четверти миллиона знаков это полтора миллисекунды.
        // Длину в байтах Swift знает сразу, и один символ занимает минимум один
        // байт: пока байт меньше предела, знаков тем более меньше, и обходить
        // строку незачем.
        if text.utf8.count > Self.maxCharacters, text.count > Self.maxCharacters {
            lastError = "Заметка длиннее \(Self.maxCharacters) символов не сохраняется."
            return
        }
        items[index].text = text
        items[index].modifiedAt = Date()
        scheduleSave()
    }

    func remove(_ note: ScratchNote) {
        guard let index = items.firstIndex(where: { $0.id == note.id }) else { return }
        items.remove(at: index)
        if selectedID == note.id { selectedID = items.first?.id }
        scheduleSave()
        openUndoWindow(PendingDeletion(item: note, index: index))
    }

    func undoDeletion() {
        guard let pending = pendingDeletion else { return }
        undoWindow?.cancel()
        pendingDeletion = nil
        items.insert(pending.item, at: min(pending.index, items.count))
        selectedID = pending.item.id
        scheduleSave()
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try store.save(items)
            lastError = nil
        } catch {
            lastError = "Не удалось сохранить заметки: \(error.localizedDescription)"
        }
    }

    func clear() {
        undoWindow?.cancel()
        pendingDeletion = nil
        items.removeAll()
        selectedID = nil
        flush()
    }

    private func openUndoWindow(_ pending: PendingDeletion<ScratchNote>) {
        undoWindow?.cancel()
        pendingDeletion = pending
        undoWindow = Task { [weak self] in
            try? await Task.sleep(for: PendingDeletion<ScratchNote>.window)
            guard !Task.isCancelled else { return }
            self?.pendingDeletion = nil
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}
