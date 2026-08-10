import AppKit

struct ShelfItem: Identifiable, Equatable {
    enum Location: Codable, Equatable {
        case securityScopedBookmark(Data)
        case ownedFile(String)
    }

    let id: UUID
    let location: Location
    /// nil, пока файл недоступен: том не смонтирован, файл выгружен из iCloud
    /// или лежит на отключённой шаре. Запись при этом остаётся на полке —
    /// выбрасывать её вправе только пользователь.
    let url: URL?
    let name: String
    let addedAt: Date

    var isAvailable: Bool { url != nil }

    /// Только по расширению: isExecutableFile для файла вне контейнера
    /// вызывается без открытого доступа и всегда отвечает «нет», то есть
    /// половина проверки просто не работала. webloc и url добавлены потому,
    /// что открывают произвольную ссылку без всякого предупреждения.
    var isPotentiallyExecutable: Bool {
        let extensions = ["app", "pkg", "command", "workflow", "scpt", "dmg", "webloc", "url", "sh", "tool"]
        return extensions.contains((name as NSString).pathExtension.lowercased())
    }
}

private struct StoredShelfItem: Codable {
    let id: UUID
    let location: ShelfItem.Location
    let addedAt: Date
    /// Появилось позже: без имени недоступный элемент нечем показать. Optional,
    /// чтобы уже сохранённые полки читались без миграции.
    var name: String?
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    /// Порядок по умолчанию — свежее сверху.
    var ordered: [ShelfItem] { items.sorted { $0.addedAt > $1.addedAt } }
    @Published var lastError: String?

    private let store = AtomicJSONStore<[StoredShelfItem]>(
        url: ApplicationPaths.supportDirectory.appendingPathComponent("shelf.json")
    )

    /// Загрузка ничего не удаляет и по умолчанию ничего не пишет. Раньше здесь
    /// отсеивались неразрешившиеся закладки, и результат отсева тут же
    /// сохранялся — отключённый диск стоил записи навсегда.
    func load() {
        let result = store.load(default: [])
        var refreshedBookmarks = false
        items = result.value.map { stored in
            let resolved = resolve(stored)
            if resolved.location != stored.location { refreshedBookmarks = true }
            return resolved
        }

        if let backup = result.corruptedBackup {
            lastError = "Список полки был повреждён. Прежний файл сохранён: \(backup.lastPathComponent)"
        }
        // Единственная причина писать при загрузке — обновлённые закладки.
        if refreshedBookmarks { persist() }
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
                    ShelfItem(
                        id: UUID(),
                        location: .securityScopedBookmark(bookmark),
                        url: url,
                        name: url.lastPathComponent,
                        addedAt: Date()
                    ),
                    at: 0
                )
                lastError = nil
            } catch {
                // Локализованный текст один и тот же для десятка разных причин,
                // поэтому домен и код показываем прямо в интерфейсе: без них
                // разбор такой ошибки на чужой машине превращается в гадание.
                let failure = error as NSError
                lastError = "Не удалось сохранить доступ к \(url.lastPathComponent): "
                    + "\(failure.localizedDescription) [\(failure.domain) \(failure.code)]"
            }
        }
        persist()
    }

    func addOwnedFile(_ url: URL) {
        guard isInsideVault(url), !items.contains(where: { $0.url == url }) else { return }
        items.insert(
            ShelfItem(
                id: UUID(),
                location: .ownedFile(url.path),
                url: url,
                name: url.lastPathComponent,
                addedAt: Date()
            ),
            at: 0
        )
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
        guard item.isAvailable else {
            lastError = "«\(item.name)» сейчас недоступен."
            return false
        }
        guard allowingExecutables || !item.isPotentiallyExecutable else {
            lastError = "Исполняемые файлы открываются только после отдельного подтверждения."
            return false
        }
        lastError = nil
        return withAccess(to: item) { NSWorkspace.shared.open($0) } ?? false
    }

    /// Puts the file itself on the pasteboard, so pasting in Finder produces a
    /// copy of it rather than a line of text with its path.
    func copy(_ item: ShelfItem) {
        withAccess(to: item) { url in
            InternalPasteboard.write { $0.writeObjects([url as NSURL]) }
        }
    }

    private func resolve(_ stored: StoredShelfItem) -> ShelfItem {
        switch stored.location {
        case .ownedFile(let path):
            let url = URL(fileURLWithPath: path)
            let exists = isInsideVault(url) && FileManager.default.fileExists(atPath: url.path)
            return ShelfItem(
                id: stored.id,
                location: stored.location,
                url: exists ? url : nil,
                name: stored.name ?? url.lastPathComponent,
                addedAt: stored.addedAt
            )

        case .securityScopedBookmark(let data):
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return unavailable(stored)
            }

            // Существование файла вне контейнера можно проверить только с
            // открытым доступом: без него ответ всегда «нет».
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return unavailable(stored, name: url.lastPathComponent)
            }

            // isStale по контракту Apple означает «ссылка ещё верна, закладку
            // пересоздай», а не «выбрасывай запись».
            var location = stored.location
            if isStale, let refreshed = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                relativeTo: nil
            ) {
                location = .securityScopedBookmark(refreshed)
            }

            return ShelfItem(
                id: stored.id,
                location: location,
                url: url,
                name: url.lastPathComponent,
                addedAt: stored.addedAt
            )
        }
    }

    private func unavailable(_ stored: StoredShelfItem, name: String? = nil) -> ShelfItem {
        ShelfItem(
            id: stored.id,
            location: stored.location,
            url: nil,
            name: name ?? stored.name ?? "Недоступный файл",
            addedAt: stored.addedAt
        )
    }

    private func persist() {
        do {
            try store.save(items.map {
                StoredShelfItem(id: $0.id, location: $0.location, addedAt: $0.addedAt, name: $0.name)
            })
        } catch {
            lastError = "Не удалось сохранить список полки: \(error.localizedDescription)"
        }
    }

    private func withAccess<Result>(to item: ShelfItem, perform: (URL) -> Result) -> Result? {
        guard let url = item.url else { return nil }
        guard case .securityScopedBookmark = item.location else { return perform(url) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return perform(url)
    }

    private func isInsideVault(_ url: URL) -> Bool {
        let root = ApplicationPaths.clipboardVault.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }
}
