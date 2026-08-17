import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Curty

final class SecurityBoundaryTests: XCTestCase {
    func testMeetingLinksRequireHTTPSAndApprovedHost() {
        XCTAssertNotNil(MeetingURLPolicy.validate(URL(string: "https://meet.google.com/abc-defg-hij")!))
        XCTAssertNotNil(MeetingURLPolicy.validate(URL(string: "https://subdomain.zoom.us/j/123")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "http://meet.google.com/abc")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "file:///Applications/Calculator.app")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "https://meet.google.com.evil.example/abc")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "https://user:password@zoom.us/j/123")!))
    }

    func testMeetingDetectorSkipsUnknownLinks() {
        let text = "Agenda https://evil.example/phish then https://teams.microsoft.com/l/meetup-join/123"
        XCTAssertEqual(MeetingURLPolicy.firstApprovedURL(in: text)?.host, "teams.microsoft.com")
    }

    func testCurtysOwnWritesAreMarkedSoHistorySkipsThem() {
        // Отдельная доска, чтобы не трогать буфер обмена пользователя.
        let board = NSPasteboard(name: .init("dev.curty.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }

        board.clearContents()
        board.setString("извне", forType: .string)
        XCTAssertFalse(InternalPasteboard.containsMarker(board))

        InternalPasteboard.write(to: board) { $0.setString("из Curty", forType: .string) }
        XCTAssertTrue(InternalPasteboard.containsMarker(board))
        XCTAssertEqual(board.string(forType: .string), "из Curty")
    }

    /// Перетаскивание обязано отдавать сам файл, а не его копию. Через
    /// `.onDrag` SwiftUI это оказалось недостижимо: он копировал файл в кэш
    /// нашего контейнера и отдавал приёмнику путь туда — CapCut отвечал «нет
    /// доступа к некоторым материалам». Поэтому файл кладётся на доску
    /// средствами AppKit, своим настоящим путём.
    @MainActor
    func testDraggedFileKeepsItsRealPath() throws {
        let store = ShelfStore()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("curty-\(UUID().uuidString).txt")
        try "перетаскивание".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let item = ShelfItem(
            id: UUID(),
            location: .ownedFile(file.path),
            url: file,
            name: file.lastPathComponent,
            addedAt: Date()
        )
        let payload = try XCTUnwrap(store.beginDrag(item))
        defer { payload.release() }
        XCTAssertEqual(payload.url, file, "отдаётся сам файл, а не копия")

        // То же самое, но глазами приёмника: кладём на доску ровно так, как
        // это делает строка, и читаем обратно.
        let board = NSPasteboard(name: .init("dev.curty.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([payload.url as NSURL])

        let read = board.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        XCTAssertEqual(read.first?.standardizedFileURL, file.standardizedFileURL)
        XCTAssertFalse(
            read.first?.path.contains("/Containers/dev.curty.app/") ?? true,
            "путь не должен вести в наш контейнер: \(read.first?.path ?? "—")"
        )
    }

    /// Ответ полки решает, убирать ли запись из истории буфера. Поэтому
    /// «уже лежит» обязано считаться принятым: иначе повторный перенос того же
    /// файла оставлял бы в истории запись о том, что на полке и так есть.
    @MainActor
    func testShelfReportsWhetherTheFileEndedUpThere() throws {
        let store = ShelfStore()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("curty-\(UUID().uuidString).txt")
        try "перенос".write(to: file, atomically: true, encoding: .utf8)
        defer {
            store.items.filter { $0.url == file }.forEach { store.remove($0) }
            try? FileManager.default.removeItem(at: file)
        }

        XCTAssertTrue(store.addUserSelectedFiles([file]), "файл должен оказаться на полке")
        XCTAssertEqual(store.items.filter { $0.url == file }.count, 1)

        XCTAssertTrue(store.addUserSelectedFiles([file]), "уже лежащий файл — тоже «на полке»")
        XCTAssertEqual(store.items.filter { $0.url == file }.count, 1, "дубля быть не должно")

        let missing = file.deletingLastPathComponent()
            .appendingPathComponent("curty-нет-такого-\(UUID().uuidString).txt")
        XCTAssertFalse(store.addUserSelectedFiles([missing]), "несуществующий файл принять нельзя")
        XCTAssertNotNil(store.lastError, "отказ должен быть объяснён, а не проглочен")
    }

    func testTextTakenToTheTranslatorLeavesTheHistory() {
        let entries: [ClipboardEntry] = [
            .init(payload: .text("Xin chào"), capturedAt: Date()),
            .init(payload: .text("другое"), capturedAt: Date()),
            .init(payload: .file(URL(fileURLWithPath: "/tmp/файл")), capturedAt: Date()),
        ]

        // Краевые пробелы вставка часто приносит с собой — они не должны мешать.
        let left = ClipboardPolicy.removingText("  Xin chào\n", from: entries)
        XCTAssertEqual(left.count, 2)
        XCTAssertFalse(left.contains { if case .text(let value) = $0.payload { return value == "Xin chào" } else { return false } })

        // Пустой текст ничего не вычёркивает: иначе очистка поля стирала бы историю.
        XCTAssertEqual(ClipboardPolicy.removingText("   ", from: entries).count, 3)
        // Файлы и картинки правило не трогает.
        XCTAssertEqual(ClipboardPolicy.removingText("/tmp/файл", from: entries).count, 3)
    }

    /// Системная проверка доступности внутри песочницы врёт: она отвечала
    /// «пакета нет» на паре, которой перевод только что работал. Поэтому
    /// предложение загрузки требует двух условий сразу.
    func testDownloadIsOfferedOnlyForPairsThatNeverWorked() {
        XCTAssertTrue(TranslationLanguagePolicy.shouldOfferDownload(systemSaysMissing: true, alreadyWorked: false))
        XCTAssertFalse(TranslationLanguagePolicy.shouldOfferDownload(systemSaysMissing: true, alreadyWorked: true))
        XCTAssertFalse(TranslationLanguagePolicy.shouldOfferDownload(systemSaysMissing: false, alreadyWorked: false))
        XCTAssertEqual(TranslationLanguagePolicy.key(for: (from: "vi", to: "ru")), "vi>ru")
    }

    func testClipboardSensitiveTypesAreIgnored() {
        XCTAssertTrue(ClipboardPolicy.shouldIgnore(typeNames: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardPolicy.shouldIgnore(typeNames: ["org.nspasteboard.TransientType"]))
        XCTAssertFalse(ClipboardPolicy.shouldIgnore(typeNames: ["public.utf8-plain-text"]))
    }

    func testClipboardImageLimitsRejectInvalidAndOversizedPayloads() {
        XCTAssertFalse(ClipboardPolicy.acceptsImage(Data()))
        XCTAssertFalse(ClipboardPolicy.acceptsImage(Data(repeating: 0, count: ClipboardPolicy.maxImageBytes + 1)))
        XCTAssertTrue(ClipboardPolicy.acceptsImage(makePNG(width: 2, height: 2)))
    }

    func testCorruptedFileIsSetAsideInsteadOfDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurtyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("notes.json")
        try Data("{ это не json".utf8).write(to: url)

        let store = AtomicJSONStore<[String]>(url: url)
        let result = store.load(default: ["запасное"])

        XCTAssertEqual(result.value, ["запасное"])
        // Главное: испорченный файл никуда не делся, его можно разобрать руками.
        let backup = try XCTUnwrap(result.corruptedBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{ это не json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUndoWindowIsLongEnoughToNotice() {
        // Четыре секунды: успеть заметить промах, но не держать полосу на экране.
        XCTAssertEqual(PendingDeletion<String>.window, .seconds(4))
    }

    @MainActor
    func testDeletedNoteComesBackToItsOwnPlace() {
        let store = NoteStore()
        store.add()
        store.add()
        store.add()
        let middle = store.items[1]

        store.remove(middle)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.pendingDeletion?.item, middle)

        store.undoDeletion()
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items[1], middle, "заметка должна вернуться на своё место, а не в начало")
        XCTAssertNil(store.pendingDeletion)
    }

    @MainActor
    func testDeletedSnippetComesBackToItsOwnPlace() {
        let store = SnippetStore()
        store.add(title: "первый", body: "1")
        store.add(title: "второй", body: "2")
        store.add(title: "третий", body: "3")
        let middle = store.items[1]

        store.remove(middle)
        XCTAssertEqual(store.items.count, 2)

        store.undoDeletion()
        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items[1], middle)
        XCTAssertNil(store.pendingDeletion)
    }

    func testDisplayTimeZoneFallsBackToTheSystemUnlessDeliberatelySet() {
        // Умолчание — пустая строка: у всех, кто настройку не трогал, время
        // показывается ровно как раньше.
        XCTAssertEqual(DisplayTimeZonePolicy.resolve(identifier: "").identifier, TimeZone.current.identifier)
        XCTAssertFalse(DisplayTimeZonePolicy.isOverridden(identifier: ""))
        // Мусор в настройке не должен ломать показ времени.
        XCTAssertEqual(DisplayTimeZonePolicy.resolve(identifier: "Чепуха/Нет").identifier, TimeZone.current.identifier)

        let vietnam = "Asia/Ho_Chi_Minh"
        XCTAssertEqual(DisplayTimeZonePolicy.resolve(identifier: vietnam).identifier, vietnam)
        XCTAssertEqual(
            DisplayTimeZonePolicy.isOverridden(identifier: vietnam),
            TimeZone(identifier: vietnam)!.secondsFromGMT() != TimeZone.current.secondsFromGMT()
        )
        XCTAssertEqual(DisplayTimeZonePolicy.cityName(vietnam), "Ho Chi Minh")
    }

    func testDisplayTimeZoneChangesWhatDayItIs() {
        // 20:30 UTC — во Вьетнаме это уже следующий день, в Москве ещё нет.
        let moment = Date(timeIntervalSince1970: 1_754_598_600)
        let vietnam = DisplayTimeZonePolicy.calendar(for: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
        let moscow = DisplayTimeZonePolicy.calendar(for: TimeZone(identifier: "Europe/Moscow")!)
        XCTAssertNotEqual(
            vietnam.component(.day, from: moment),
            moscow.component(.day, from: moment),
            "календарь должен считать сутки по выбранному поясу, иначе «сегодня» разъезжается"
        )
    }

    /// Новое сверху, но дальше список неподвижен: правка не поднимает
    /// элемент. Перескакивающие строки сбивают с толку — глаз ищет запись
    /// там, где её оставил.
    @MainActor
    func testEditingDoesNotReorderLists() {
        let notes = NoteStore()
        notes.add()
        notes.add()
        let newest = notes.items[0].id
        let older = notes.items[1].id

        notes.update(older, text: "правка не должна двигать заметку")
        XCTAssertEqual(notes.items.map(\.id), [newest, older])

        let snippets = SnippetStore()
        snippets.add(title: "первый", body: "1")
        snippets.add(title: "второй", body: "2")
        XCTAssertEqual(snippets.filteredItems.map(\.title), ["второй", "первый"])

        snippets.update(snippets.items[1], title: "первый", body: "1 с правкой")
        XCTAssertEqual(snippets.filteredItems.map(\.title), ["второй", "первый"])
    }

    /// Два предела уже разъезжались: заметка допускала вдвое больше, чем
    /// принимала история, и скопированная целиком заметка молча пропадала.
    /// Вопрос про автозапуск задаётся один раз и только по делу. Повторяющийся
    /// вопрос раздражает сильнее, чем отсутствие автозапуска.
    func testLaunchAtLoginIsAskedOnceAndOnlyWhenUseful() {
        XCTAssertTrue(LaunchAtLoginPolicy.shouldAsk(alreadyAsked: false, isEnabled: false, canChange: true))
        XCTAssertFalse(LaunchAtLoginPolicy.shouldAsk(alreadyAsked: true, isEnabled: false, canChange: true))
        // Уже включён — спрашивать не о чем.
        XCTAssertFalse(LaunchAtLoginPolicy.shouldAsk(alreadyAsked: false, isEnabled: true, canChange: true))
        // Включить нельзя — вопрос был бы издевательством.
        XCTAssertFalse(LaunchAtLoginPolicy.shouldAsk(alreadyAsked: false, isEnabled: false, canChange: false))
    }

    @MainActor
    func testClipboardAcceptsEverythingANoteCanHold() {
        XCTAssertGreaterThanOrEqual(ClipboardPolicy.maxTextCharacters, NoteStore.maxCharacters)
        // Счётчик обязан появляться до предела, а не вместе с ним: иначе он
        // сообщает о беде, когда сокращать уже поздно.
        XCTAssertLessThan(NoteStore.counterThreshold, NoteStore.maxCharacters)
    }

    @MainActor
    func testCalendarShowsOnlyWhatIsStillAhead() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func meeting(_ id: String, from: TimeInterval, to: TimeInterval) -> MeetingSummary {
            MeetingSummary(
                id: id,
                title: id,
                start: now.addingTimeInterval(from),
                end: now.addingTimeInterval(to),
                calendarName: "тест",
                link: nil
            )
        }

        let visible = CalendarStore.upcoming(
            [
                meeting("прошедшая", from: -7_200, to: -3_600),
                meeting("идёт сейчас", from: -600, to: 1_800),
                meeting("впереди", from: 3_600, to: 7_200),
            ],
            now: now
        )

        // Идущая встреча не прошедшая: ссылка на неё нужна именно сейчас.
        XCTAssertEqual(visible.map(\.id), ["идёт сейчас", "впереди"])
    }

    func testUpdateIsOfferedOnlyForNewerRemoteCommits() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(UpdatePolicy.isUpdateAvailable(
            localCommit: "aaa", localDate: older, remoteCommit: "bbb", remoteDate: newer
        ))
        // Тот же коммит — обновлять нечего, даже если дата другая.
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(
            localCommit: "aaa", localDate: older, remoteCommit: "aaa", remoteDate: newer
        ))
        // Локальная сборка впереди ветки: так живёт машина автора, и кнопка
        // не должна на неё ругаться.
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(
            localCommit: "aaa", localDate: newer, remoteCommit: "bbb", remoteDate: older
        ))
        // Сборка вне git: сравнивать не с чем, предлагать нечего.
        XCTAssertFalse(UpdatePolicy.isUpdateAvailable(
            localCommit: nil, localDate: nil, remoteCommit: "bbb", remoteDate: newer
        ))
    }

    func testUpdateChecksExactlyOneAddress() {
        XCTAssertEqual(
            UpdatePolicy.latestCommitURL.absoluteString,
            "https://api.github.com/repos/AYSGODX/Curty/commits/main"
        )
    }

    /// Имя и место запускателя — единственный договор между install.sh,
    /// который его кладёт, и приложением, которое его запускает. Разъедутся —
    /// кнопка перестанет работать молча.
    func testUpdateLauncherLivesWhereTheInstallerPutsIt() throws {
        XCTAssertEqual(UpdatePolicy.launcherName, "update.sh")
        let launcher = try UpdatePolicy.launcherURL()
        XCTAssertEqual(launcher.lastPathComponent, "update.sh")
        // Вне контейнера: изнутри него запуск блокирует Gatekeeper.
        XCTAssertFalse(launcher.path.contains("/Library/Containers/"))
        // Имя папки подставляет система по идентификатору приложения, поэтому
        // под тестами оно другое — проверяем сам каталог.
        XCTAssertTrue(launcher.path.contains("/Library/Application Scripts/"))
    }

    func testAtomicJSONStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurtyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("test.json")
        let store = AtomicJSONStore<[String]>(url: url)
        try store.save(["локально", "безопасно"])
        XCTAssertEqual(store.load(default: []).value, ["локально", "безопасно"])

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    /// Нажатие на паузу обязано менять состояние на экране немедленно.
    /// Прежде оно ждало следующего опроса — до секунды, — и человек, решив,
    /// что промахнулся, жал второй раз и возвращал всё обратно.
    func testPlayPauseAnswersWithoutWaitingForThePoll() {
        let playing = MediaSnapshot(
            source: "Spotify", title: "Eyes Closed", artist: "Beartooth",
            album: "Below", isPlaying: true, duration: 206, position: 121
        )

        let paused = MediaOptimisticPolicy.applying(.togglePlayPause, to: playing)
        XCTAssertEqual(paused?.isPlaying, false)
        XCTAssertEqual(paused?.position, 121, "позиция от паузы не двигается")

        // Перемотка вперёд состояние воспроизведения не меняет, и выдумывать
        // его до ответа плеера нечего.
        XCTAssertNil(MediaOptimisticPolicy.applying(.next, to: playing))
        XCTAssertNil(MediaOptimisticPolicy.applying(.togglePlayPause, to: nil))
    }

    @MainActor
    func testUserActionIsNotSwallowedByAPollInFlight() {
        let store = MediaStore()
        // Опрос занял канал. Раньше нажатие в этот момент просто пропадало —
        // отсюда «клик по дорожке не всегда срабатывает».
        XCTAssertTrue(store.beginRequestForTesting(userInitiated: false))
        XCTAssertTrue(store.beginRequestForTesting(userInitiated: true))
        // А вот второе действие подряд ждёт: очередь из зависших скриптов
        // никому не нужна.
        XCTAssertFalse(store.beginRequestForTesting(userInitiated: true))
    }

    func testMediaVolumeStaysInRangeAndFormatsWithoutSeparators() {
        XCTAssertEqual(MediaVolumePolicy.clamp(-40), 0)
        XCTAssertEqual(MediaVolumePolicy.clamp(180), 100)
        XCTAssertEqual(MediaVolumePolicy.clamp(37), 37)

        // Плеер, не сообщивший громкость, отдаёт -1: ползунка тогда быть не должно.
        XCTAssertNil(MediaVolumePolicy.reported(-1))
        XCTAssertEqual(MediaVolumePolicy.reported(0), 0)
        XCTAssertEqual(MediaVolumePolicy.reported(101), 100)

        // Целое без разделителя: на дроби с запятой в чужой локали уже
        // обжигались с позицией трека.
        XCTAssertEqual(MediaVolumePolicy.format(37.6), "38")
        XCTAssertEqual(MediaVolumePolicy.format(1_000), "100")
        XCTAssertFalse(MediaVolumePolicy.format(37.5).contains(","))
        XCTAssertFalse(MediaVolumePolicy.format(37.5).contains("."))
    }

    func testMediaCommandsStayAFixedAllowlist() {
        XCTAssertNil(MediaCommand(rawValue: "run arbitrary script"))
        XCTAssertEqual(Set(MediaCommand.allCases.map(\.rawValue)), ["togglePlayPause", "next", "previous"])
    }

    @MainActor
    func testClipboardAndMediaAreEnabledByDefault() {
        let suiteName = "dev.curty.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = Preferences(defaults: defaults)

        XCTAssertTrue(preferences.clipboardMonitoringEnabled)
        XCTAssertTrue(preferences.mediaIntegrationEnabled)
        XCTAssertFalse(preferences.clipboardImagesEnabled)
    }

    func testTranslationLanguageDetection() {
        // Определение по содержимому, а не по алфавиту: вьетнамский и
        // английский пишутся одними буквами, и прежний счётчик кириллицы
        // против латиницы записывал вьетнамский в английский.
        XCTAssertEqual(TranslationLanguagePolicy.detect("Xin chào, bạn khỏe không?"), "vi")
        XCTAssertEqual(TranslationLanguagePolicy.detect("Привет, как дела?"), "ru")
        XCTAssertEqual(TranslationLanguagePolicy.detect("Guten Morgen, wie geht es dir?"), "de")
        // На двух символах гадать бессмысленно.
        XCTAssertNil(TranslationLanguagePolicy.detect("ok"))

        // Переводить нечего, если язык не определён или совпадает с целевым.
        XCTAssertNil(TranslationLanguagePolicy.pair(source: nil, target: "ru"))
        XCTAssertNil(TranslationLanguagePolicy.pair(source: "ru", target: "ru"))
        XCTAssertEqual(TranslationLanguagePolicy.pair(source: "vi", target: "ru")?.from, "vi")
    }

    func testPanelActivationZoneAndCloseTiming() {
        let frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let fallback = PanelInteractionPolicy.activationRect(
            screenFrame: frame,
            safeAreaTop: 0,
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )
        // Без выреза зона намеренно тонкая и живёт по центру верхнего края:
        // курсор должен упереться в край экрана, а не проехать мимо.
        XCTAssertFalse(fallback.contains(NSPoint(x: frame.midX, y: frame.maxY - 20)))
        XCTAssertTrue(fallback.contains(NSPoint(x: frame.midX, y: frame.maxY - 1)))
        XCTAssertFalse(fallback.contains(NSPoint(x: frame.minX + 10, y: frame.maxY - 1)))
        XCTAssertLessThanOrEqual(fallback.height, 8)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.sampleInterval, 1.0 / 60.0)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.closeDelay, 0.225)
        XCTAssertGreaterThan(PanelInteractionPolicy.idleSampleInterval, PanelInteractionPolicy.sampleInterval)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.idleSampleInterval, 0.15)

        let notch = PanelInteractionPolicy.activationRect(
            screenFrame: frame,
            safeAreaTop: 38,
            leftAuxiliaryArea: NSRect(x: 0, y: 862, width: 620, height: 38),
            rightAuxiliaryArea: NSRect(x: 820, y: 862, width: 620, height: 38)
        )
        XCTAssertTrue(notch.contains(NSPoint(x: 720, y: 880)))
        XCTAssertGreaterThan(notch.width, 200)
        // Нижняя граница зоны совпадает с нижней кромкой выреза: на пункт выше
        // — ещё вырез, на пункт ниже — уже обычный экран.
        XCTAssertTrue(notch.contains(NSPoint(x: 720, y: frame.maxY - 38 + 1)))
        XCTAssertFalse(notch.contains(NSPoint(x: 720, y: frame.maxY - 38 - 1)))

        // The cursor reaches exactly frame.maxY when shoved into the top edge.
        XCTAssertTrue(fallback.contains(NSPoint(x: frame.midX, y: frame.maxY)))
        XCTAssertTrue(notch.contains(NSPoint(x: 720, y: frame.maxY)))
    }

    func testSeekValueIsClampedAndRenderedAsBareDigits() {
        XCTAssertEqual(MediaSeekPolicy.clamp(-5, duration: 200), 0)
        XCTAssertEqual(MediaSeekPolicy.clamp(500, duration: 200), 200)
        XCTAssertEqual(MediaSeekPolicy.clamp(42, duration: 200), 42)
        XCTAssertEqual(MediaSeekPolicy.clamp(.nan, duration: 200), 0)
        XCTAssertEqual(MediaSeekPolicy.clamp(42, duration: 0), 0)

        // A comma or any non-numeric character here would land inside the script.
        let rendered = MediaSeekPolicy.format(163.983993)
        XCTAssertEqual(rendered, "163.984")
        XCTAssertTrue(rendered.allSatisfy { $0.isNumber || $0 == "." })
        XCTAssertEqual(MediaSeekPolicy.format(.infinity), "0.000")
        XCTAssertEqual(MediaSeekPolicy.format(-1), "0.000")
    }

    @MainActor
    func testSettingsIsATabRatherThanASeparateWindow() {
        // Settings must stay reachable as a panel tab, but out of the tool list.
        XCTAssertTrue(AppModel.Tool.allCases.contains(.settings))
        XCTAssertFalse(AppModel.Tool.primary.contains(.settings))
        XCTAssertEqual(AppModel.Tool.primary.count, AppModel.Tool.allCases.count - 1)
        XCTAssertFalse(AppModel.Tool.settings.symbol.isEmpty)
        XCTAssertFalse(AppModel.Tool.settings.title.isEmpty)
    }

    @MainActor
    func testToolOrderSurvivesStaleAndBrokenStoredValues() {
        let available = AppModel.Tool.primary

        XCTAssertEqual(ToolOrderPolicy.resolve(stored: [], available: available), available)

        // Unknown names, duplicates and a tool that is not on the rail are dropped,
        // and anything the stored order omits still shows up at the end.
        let messy = ["clipboard", "clipboard", "нет-такого", "settings", "media"]
        let resolved = ToolOrderPolicy.resolve(stored: messy, available: available)
        XCTAssertEqual(resolved.prefix(2).map(\.rawValue), ["clipboard", "media"])
        XCTAssertEqual(Set(resolved), Set(available))
        XCTAssertEqual(resolved.count, available.count)

        let toFront = ToolOrderPolicy.move(.notes, toIndex: 0, in: available)
        XCTAssertEqual(toFront.first, .notes)
        XCTAssertEqual(Set(toFront), Set(available))
        XCTAssertEqual(toFront.count, available.count)

        // Dragging past either end parks the icon at the end, never drops it.
        let toBack = ToolOrderPolicy.move(.media, toIndex: 99, in: available)
        XCTAssertEqual(toBack.last, .media)
        XCTAssertEqual(toBack.count, available.count)
        let clampedLow = ToolOrderPolicy.move(.notes, toIndex: -5, in: available)
        XCTAssertEqual(clampedLow.first, .notes)
        XCTAssertEqual(ToolOrderPolicy.move(.media, toIndex: 0, in: available), available)
    }

    func testCalendarHorizonSpansDayAndWeek() {
        XCTAssertEqual(CalendarStore.Horizon.day.duration, 24 * 60 * 60)
        XCTAssertEqual(CalendarStore.Horizon.week.duration, 7 * 24 * 60 * 60)
        XCTAssertGreaterThan(CalendarStore.Horizon.week.limit, CalendarStore.Horizon.day.limit)
        XCTAssertEqual(Set(CalendarStore.Horizon.allCases.map(\.title)), ["Сутки", "Неделя"])
    }

    func testOverlayThresholdClearsEveryMeasuredDesktopState() {
        // Measured on this platform. A threshold that suppressed the middle
        // case is what left the notch dead on a bare desktop.
        let appCoversScreen = 0
        let bareDesktop = 1
        let missionControl = 3

        XCTAssertLessThan(appCoversScreen, SystemOverlayPolicy.overlayWindowCount)
        XCTAssertLessThan(bareDesktop, SystemOverlayPolicy.overlayWindowCount)
        XCTAssertGreaterThanOrEqual(missionControl, SystemOverlayPolicy.overlayWindowCount)
    }

    func testArtworkURLsAreRestrictedToThePlayersImageHost() {
        XCTAssertNotNil(ArtworkURLPolicy.validate("https://i.scdn.co/image/ab67616d0000b273d1bf"))
        XCTAssertNotNil(ArtworkURLPolicy.validate("  https://i.scdn.co/image/abc  "))

        XCTAssertNil(ArtworkURLPolicy.validate(""))
        XCTAssertNil(ArtworkURLPolicy.validate("http://i.scdn.co/image/abc"))
        XCTAssertNil(ArtworkURLPolicy.validate("https://evil.example/image/abc"))
        XCTAssertNil(ArtworkURLPolicy.validate("https://i.scdn.co.evil.example/image/abc"))
        XCTAssertNil(ArtworkURLPolicy.validate("https://user:secret@i.scdn.co/image/abc"))
        XCTAssertNil(ArtworkURLPolicy.validate("file:///etc/passwd"))
    }

    func testOverlayWindowMustCoverMostOfTheDisplay() {
        let screen = CGSize(width: 1_512, height: 982)
        XCTAssertTrue(SystemOverlayPolicy.coversDisplay(width: 1_512, height: 982, screenSize: screen))
        XCTAssertFalse(SystemOverlayPolicy.coversDisplay(width: 1_512, height: 90, screenSize: screen))
        XCTAssertFalse(SystemOverlayPolicy.coversDisplay(width: 1_512, height: 982, screenSize: .zero))
    }

    func testLaunchAtLoginRecognizesSupportedApplicationFolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertTrue(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Applications/Curty.app"),
            homeDirectory: home
        ))
        XCTAssertTrue(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Applications/Curty.app"),
            homeDirectory: home
        ))
        XCTAssertFalse(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/Curty.app"),
            homeDirectory: home
        ))
    }

    func testLaunchAtLoginErrorIsFriendlyAndLocalized() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 22)
        let message = LaunchAtLoginPolicy.friendlyMessage(
            for: error,
            bundleURL: URL(fileURLWithPath: "/tmp/Curty.app")
        )
        XCTAssertTrue(message.contains("Программы"))
        XCTAssertFalse(message.contains("Invalid argument"))
    }

    private func makePNG(width: Int, height: Int) -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return representation.representation(using: .png, properties: [:])!
    }
}
