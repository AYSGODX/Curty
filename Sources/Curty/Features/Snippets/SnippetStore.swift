import AppKit

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var tags: [String]
    var modifiedAt: Date
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var items: [Snippet] = []
    @Published var query = ""
    @Published var lastError: String?

    private let store = AtomicJSONStore<[Snippet]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("snippets.json")
    )

    var filteredItems: [Snippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.body.localizedCaseInsensitiveContains(needle)
                || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    func load() { items = store.load(default: []) }

    func add(title: String, body: String, tags: [String] = []) {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        items.insert(
            Snippet(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: value,
                tags: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                modifiedAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func update(_ snippet: Snippet, title: String, body: String, tags: [String]) {
        guard let index = items.firstIndex(where: { $0.id == snippet.id }) else { return }
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].body = body
        items[index].tags = tags
        items[index].modifiedAt = Date()
        persist()
    }

    func remove(_ snippet: Snippet) {
        items.removeAll { $0.id == snippet.id }
        persist()
    }

    func copy(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.body, forType: .string)
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        do { try store.save(items) } catch { lastError = error.localizedDescription }
    }
}
