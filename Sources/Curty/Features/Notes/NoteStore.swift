import Foundation

struct ScratchNote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var modifiedAt: Date
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var items: [ScratchNote] = []
    @Published var selectedID: UUID?
    @Published var lastError: String?

    private let store = AtomicJSONStore<[ScratchNote]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("notes.json")
    )
    private var pendingSave: DispatchWorkItem?

    func load() {
        items = store.load(default: [])
        selectedID = items.first?.id
    }

    func add() {
        let note = ScratchNote(id: UUID(), text: "", modifiedAt: Date())
        items.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    func update(_ id: UUID, text: String) {
        guard text.count <= 250_000, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        items[index].modifiedAt = Date()
        scheduleSave()
    }

    func remove(_ note: ScratchNote) {
        items.removeAll { $0.id == note.id }
        if selectedID == note.id { selectedID = items.first?.id }
        scheduleSave()
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        do { try store.save(items) } catch { lastError = error.localizedDescription }
    }

    func clear() {
        items.removeAll()
        selectedID = nil
        flush()
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
