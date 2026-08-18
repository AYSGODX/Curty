import AppKit
import UniformTypeIdentifiers

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

    var isPotentiallyExecutable: Bool { ExecutableFilePolicy.isPotentiallyExecutable(name) }
}

/// Что полка считает потенциально исполняемым — то, что открывается не
/// просмотром, а действием: запуском, установкой, переходом по ссылке.
/// Проверка только по имени: isExecutableFile для файла вне контейнера
/// вызывается без открытого доступа и всегда отвечает «нет», то есть
/// половина такой проверки просто не работала.
enum ExecutableFilePolicy {
    /// Прямой список — страховка на случаи, которых система не знает.
    /// Файлы-ссылки (webloc, url, inetloc, fileloc) здесь потому, что
    /// открывают произвольный адрес без всякого предупреждения; terminal —
    /// потому, что несёт команду запуска в настройках Терминала.
    static let extensions: Set<String> = [
        "app", "pkg", "mpkg", "xip", "command", "workflow", "tool",
        "scpt", "scptd", "applescript", "jar", "sh", "dmg",
        "webloc", "url", "inetloc", "fileloc", "terminal",
    ]

    /// Семейства типов закрывают целые классы разом — скрипты любого языка,
    /// образы дисков, интернет-ссылки, — а не отдельные написания.
    private static let dangerousTypes: [UTType] = [
        .executable, .script, .diskImage, .internetLocation,
    ]

    static func isPotentiallyExecutable(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if extensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return dangerousTypes.contains { type.conforms(to: $0) }
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
    @Published var lastError: String?

    private let store: AtomicJSONStore<[StoredShelfItem]>
    /// Каталог собственных файлов полки — снимков, сохранённых из буфера.
    private let vaultDirectory: URL

    /// Пути хранения подставляются в тестах: swift test не имеет права
    /// работать с настоящей папкой Application Support пользователя — а до
    /// того, как каталог стал параметром, работал и переписывал её.
    init(
        directory: URL = ApplicationPaths.supportDirectory,
        vault: URL = ApplicationPaths.clipboardVault
    ) {
        store = AtomicJSONStore(url: directory.appendingPathComponent("shelf.json"))
        vaultDirectory = vault
    }

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
        // После повреждённого файла не подметаем: записи о снимках лежали
        // именно в нём, и сами файлы — всё, что от них осталось.
        if result.corruptedBackup == nil { sweepOrphanedVaultFiles() }
    }

    /// Отвечает, лежат ли теперь на полке все переданные файлы. Уже лежавший
    /// считается принятым: спрашивают не «добавил ли ты», а «есть ли он там» —
    /// от этого зависит, можно ли убирать запись из истории буфера.
    @discardableResult
    func addUserSelectedFiles(_ urls: [URL]) -> Bool {
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
        return urls.allSatisfy { url in items.contains { $0.url == url } }
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
        deleteOwnedFile(of: item)
        persist()
    }

    /// Чужие файлы остаются на диске — полка держала лишь закладки. Свои
    /// снимки уходят вместе с записями: кроме полки, их никто не видит.
    func clearReferences() {
        let removed = items
        items.removeAll()
        removed.forEach { deleteOwnedFile(of: $0) }
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
        copy([item])
    }

    /// Несколько файлов кладутся в буфер одной записью: вставка в Finder
    /// принесёт их все разом. Доступ открывается сразу ко всем и держится до
    /// конца записи — иначе к моменту вставки часть ссылок уже закрыта.
    func copy(_ items: [ShelfItem]) {
        let available = items.filter(\.isAvailable)
        guard !available.isEmpty else { return }

        var opened: [URL] = []
        defer { opened.forEach { $0.stopAccessingSecurityScopedResource() } }

        var urls: [NSURL] = []
        for item in available {
            guard let url = item.url else { continue }
            if case .securityScopedBookmark = item.location, url.startAccessingSecurityScopedResource() {
                opened.append(url)
            }
            urls.append(url as NSURL)
        }

        guard !urls.isEmpty else { return }
        InternalPasteboard.write { $0.writeObjects(urls) }
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

    /// Файл и право на него для перетаскивания.
    ///
    /// Перетаскивание идёт средствами AppKit, а не через `.onDrag` SwiftUI.
    /// У того обнаружилось поведение, которое ломало приём в чужих
    /// приложениях: он копировал файл в кэш нашего контейнера и отдавал
    /// приёмнику путь туда. Замер приёмником в песочнице показал это дословно
    /// — `…/Containers/dev.curty.app/…/Caches/com.apple.SwiftUI.Drag-*/имя.mp4`.
    /// Путь в чужой контейнер требует отдельного разрешения от каждого, кто
    /// его открывает, и живёт недолго: CapCut отвечал «нет доступа к
    /// некоторым материалам», а приложения с полным доступом к диску читали —
    /// отсюда и «иногда работает». Отдать вместо копии ссылку на оригинал
    /// средствами SwiftUI не вышло: с ней копия возвращалась.
    ///
    /// Здесь на доску кладётся сам файл, своим настоящим путём. Право на него
    /// полка держит по закладке, поэтому доступ открывается на время сессии и
    /// закрывается, когда перетаскивание закончилось.
    func beginDrag(_ items: [ShelfItem]) -> RowDragPayload? {
        var urls: [URL] = []
        var opened: [URL] = []
        for item in items {
            guard let url = item.url else { continue }
            if case .securityScopedBookmark = item.location, url.startAccessingSecurityScopedResource() {
                opened.append(url)
            }
            urls.append(url)
        }
        // Недоступные записи молча пропущены: перетаскивание везёт то, что
        // есть. Не осталось ничего — нет и перетаскивания.
        guard !urls.isEmpty else { return nil }
        return RowDragPayload(urls: urls) {
            opened.forEach { $0.stopAccessingSecurityScopedResource() }
        }
    }

    private func withAccess<Result>(to item: ShelfItem, perform: (URL) -> Result) -> Result? {
        guard let url = item.url else { return nil }
        guard case .securityScopedBookmark = item.location else { return perform(url) }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return perform(url)
    }

    /// Собственный файл полки живёт только ради своей записи: сняли запись —
    /// удаляется и файл. Иначе хранилище копит невидимые снимки до упора в
    /// лимит 250 МБ, и «удаление» не освобождает ни байта.
    private func deleteOwnedFile(of item: ShelfItem) {
        guard case .ownedFile(let path) = item.location else { return }
        let url = URL(fileURLWithPath: path)
        // Пути из файла состояния не доверяем: удалять можно только внутри
        // своего хранилища.
        guard isInsideVault(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Файл без записи на полке не нужен никому: он пережил свою запись из-за
    /// прежней ошибки или сбоя между двумя записями. Подметаем при загрузке —
    /// единственный момент, когда список заведомо полон и никто не пишет.
    private func sweepOrphanedVaultFiles() {
        let referenced = Set(items.compactMap { item -> String? in
            guard case .ownedFile(let path) = item.location else { return nil }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: vaultDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }
        for file in files {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  !referenced.contains(file.resolvingSymlinksInPath().standardizedFileURL.path)
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func isInsideVault(_ url: URL) -> Bool {
        let root = vaultDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }
}
