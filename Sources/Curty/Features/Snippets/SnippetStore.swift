import AppKit

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var modifiedAt: Date
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var items: [Snippet] = []
    @Published var query = ""
    @Published var lastError: String?
    @Published private(set) var pendingDeletion: PendingDeletion<Snippet>?

    private let store = AtomicJSONStore<[Snippet]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("snippets.json")
    )
    private var undoWindow: Task<Void, Never>?

    var filteredItems: [Snippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.body.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Порядок по умолчанию — свежее сверху. По времени изменения, а не
    /// добавления: правка поднимает сниппет наверх.
    var ordered: [Snippet] { filteredItems.sorted { $0.modifiedAt > $1.modifiedAt } }

    func load() {
        let result = store.load(default: [])
        items = result.value
        if let backup = result.corruptedBackup {
            lastError = "Файл сниппетов был повреждён. Прежний сохранён: \(backup.lastPathComponent)"
        }
    }

    func add(title: String, body: String) {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        items.insert(
            Snippet(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: value,
                modifiedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func update(_ snippet: Snippet, title: String, body: String) {
        guard let index = items.firstIndex(where: { $0.id == snippet.id }) else { return }
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].body = body
        items[index].modifiedAt = Date()
        persist()
    }

    func remove(_ snippet: Snippet) {
        guard let index = items.firstIndex(where: { $0.id == snippet.id }) else { return }
        items.remove(at: index)
        persist()
        openUndoWindow(PendingDeletion(item: snippet, index: index))
    }

    func undoDeletion() {
        guard let pending = pendingDeletion else { return }
        undoWindow?.cancel()
        pendingDeletion = nil
        items.insert(pending.item, at: min(pending.index, items.count))
        persist()
    }

    func copy(_ snippet: Snippet) {
        // Сниппет уже хранится в Curty, поэтому его копия в истории буфера была
        // бы дубликатом — как и файл с полки.
        InternalPasteboard.write { $0.setString(snippet.body, forType: .string) }
    }

    func clear() {
        undoWindow?.cancel()
        pendingDeletion = nil
        items.removeAll()
        persist()
    }

    private func openUndoWindow(_ pending: PendingDeletion<Snippet>) {
        undoWindow?.cancel()
        pendingDeletion = pending
        undoWindow = Task { [weak self] in
            try? await Task.sleep(for: PendingDeletion<Snippet>.window)
            guard !Task.isCancelled else { return }
            self?.pendingDeletion = nil
        }
    }

    private func persist() {
        do {
            try store.save(items)
            lastError = nil
        } catch {
            lastError = "Не удалось сохранить сниппеты: \(error.localizedDescription)"
        }
    }
}
