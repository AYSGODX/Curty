import AppKit

struct ShelfItem: Identifiable, Equatable {
    enum Location: Codable, Equatable {
        case securityScopedBookmark(Data)
        case ownedFile(String)
    }

    let id: UUID
    let location: Location
    let url: URL
    let addedAt: Date

    var name: String { url.lastPathComponent }

    var isPotentiallyExecutable: Bool {
        let extensions = ["app", "pkg", "command", "workflow", "scpt", "dmg"]
        return extensions.contains(url.pathExtension.lowercased()) || FileManager.default.isExecutableFile(atPath: url.path)
    }
}

private struct StoredShelfItem: Codable {
    let id: UUID
    let location: ShelfItem.Location
    let addedAt: Date
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var lastError: String?

    private let store = AtomicJSONStore<[StoredShelfItem]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("shelf.json")
    )

    func load() {
        items = store.load(default: []).compactMap(resolve)
        persist()
    }

    func addUserSelectedFiles(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                    relativeTo: nil
                )
                items.insert(
                    ShelfItem(id: UUID(), location: .securityScopedBookmark(bookmark), url: url, addedAt: Date()),
                    at: 0
                )
            } catch {
                lastError = "Не удалось сохранить доступ к \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        persist()
    }

    func addOwnedFile(_ url: URL) {
        guard isInsideVault(url), !items.contains(where: { $0.url == url }) else { return }
        items.insert(ShelfItem(id: UUID(), location: .ownedFile(url.path), url: url, addedAt: Date()), at: 0)
        persist()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clearReferences() {
        items.removeAll()
        persist()
    }

    func reveal(_ item: ShelfItem) {
        withAccess(to: item) { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    }

    @discardableResult
    func open(_ item: ShelfItem, allowingExecutables: Bool = false) -> Bool {
        guard allowingExecutables || !item.isPotentiallyExecutable else {
            lastError = "Исполняемые файлы открываются только после отдельного подтверждения."
            return false
        }
        return withAccess(to: item) { NSWorkspace.shared.open($0) }
    }

    func copyPath(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path, forType: .string)
    }

    private func resolve(_ stored: StoredShelfItem) -> ShelfItem? {
        switch stored.location {
        case .ownedFile(let path):
            let url = URL(fileURLWithPath: path)
            guard isInsideVault(url), FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: stored.id, location: stored.location, url: url, addedAt: stored.addedAt)
        case .securityScopedBookmark(let data):
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else { return nil }

            // Whether a file outside the container exists can only be answered
            // with the scope open. Asking without it always says "no", which
            // quietly emptied the shelf on every launch.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(id: stored.id, location: stored.location, url: url, addedAt: stored.addedAt)
        }
    }

    private func persist() {
        do {
            try store.save(items.map { StoredShelfItem(id: $0.id, location: $0.location, addedAt: $0.addedAt) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func withAccess<Result>(to item: ShelfItem, perform: (URL) -> Result) -> Result {
        guard case .securityScopedBookmark = item.location else { return perform(item.url) }
        let access = item.url.startAccessingSecurityScopedResource()
        defer { if access { item.url.stopAccessingSecurityScopedResource() } }
        return perform(item.url)
    }

    private func isInsideVault(_ url: URL) -> Bool {
        let root = ApplicationPaths.clipboardVault.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }
}
