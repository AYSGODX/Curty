import AppKit

enum UpdateState: Equatable {
    case unknown
    case checking
    case upToDate
    case available(commit: String, date: Date)
    case failed(String)
}

/// Curty живёт в песочнице и обновить себя не может: писать за пределы своего
/// контейнера ей нельзя, а новая версия ещё и собирается из исходников. Поэтому
/// приложение умеет ровно две вещи — узнать, что на GitHub есть коммит новее
/// собственной сборки, и открыть скрипт обновления в Терминале, который
/// работает уже без песочницы.
enum UpdatePolicy {
    static let repository = "AYSGODX/Curty"
    static let apiHost = "api.github.com"

    static var latestCommitURL: URL {
        URL(string: "https://\(apiHost)/repos/\(repository)/commits/main")!
    }

    /// Разные хеши сами по себе ничего не значат: локальная сборка бывает
    /// впереди ветки — так живёт машина автора. Обновление есть только тогда,
    /// когда удалённый коммит действительно новее собранного.
    static func isUpdateAvailable(
        localCommit: String?,
        localDate: Date?,
        remoteCommit: String,
        remoteDate: Date
    ) -> Bool {
        guard let localCommit, !localCommit.isEmpty else { return false }
        guard localCommit != remoteCommit else { return false }
        guard let localDate else { return true }
        return remoteDate > localDate
    }

    /// Имя запускателя, который кладёт Scripts/install.sh. Живёт он в
    /// ~/Library/Application Scripts — единственном месте, откуда песочное
    /// приложение может запустить что-то вне своей песочницы. Свой контейнер
    /// не годится: macOS помечает его карантином целиком, и Gatekeeper
    /// объявляет любой запуск оттуда повреждённым приложением.
    static let launcherName = "update.sh"

    static func launcherURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent(launcherName)
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .unknown

    /// Вшивается в Info.plist сборкой: без этих трёх значений сравнивать не с
    /// чем и обновлять нечего.
    let buildCommit: String?
    let buildDate: Date?

    private var lastCheck: Date?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary
        buildCommit = (info?["CurtyBuildCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        buildDate = (info?["CurtyBuildCommitDate"] as? String).flatMap(Self.parseDate)
    }

    var shortCommit: String? { buildCommit.map { String($0.prefix(7)) } }

    var canInstallUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    /// Настройки открывают вкладку часто, а лимит GitHub для анонимных запросов
    /// — шестьдесят в час на адрес. Раз в полчаса более чем достаточно.
    func checkIfStale() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 30 * 60, state != .unknown { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        // Отметка до всех выходов: троттлинг обязан работать и для сборки
        // вне git, иначе её «проверка» повторяется при каждом заходе.
        lastCheck = Date()
        guard let buildCommit else {
            state = .failed("Сборка сделана вне git-репозитория, сравнивать не с чем.")
            return
        }

        state = .checking
        let session = session
        let localDate = buildDate

        Task {
            do {
                let latest = try await Self.fetchLatestCommit(using: session)
                state = UpdatePolicy.isUpdateAvailable(
                    localCommit: buildCommit,
                    localDate: localDate,
                    remoteCommit: latest.sha,
                    remoteDate: latest.date
                )
                    ? .available(commit: String(latest.sha.prefix(7)), date: latest.date)
                    : .upToDate
            } catch {
                state = .failed("Не удалось проверить обновления: \(error.localizedDescription)")
            }
        }
    }

    /// Возвращает true, если обновление действительно запущено: панель
    /// закрывается только тогда, иначе сообщение об ошибке уедет вместе с ней.
    @discardableResult
    func startUpdate() -> Bool {
        guard let launcher = try? UpdatePolicy.launcherURL(),
              FileManager.default.isExecutableFile(atPath: launcher.path) else {
            state = .failed("Запускатель обновления не найден. Выполните один раз вручную: git pull && Scripts/install.sh — он положит его на место.")
            return false
        }

        do {
            // NSUserUnixTask — единственный способ для песочного приложения
            // запустить что-то вне песочницы. Собрать и переустановить себя
            // Curty иначе не может: обычный дочерний процесс унаследовал бы её
            // ограничения и не добрался бы ни до репозитория, ни до /Applications.
            let task = try NSUserUnixTask(url: launcher)
            task.execute(withArguments: nil) { error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    self?.state = .failed("Не удалось запустить обновление: \(error.localizedDescription)")
                }
            }
            return true
        } catch {
            state = .failed("Не удалось запустить обновление: \(error.localizedDescription)")
            return false
        }
    }

    private struct LatestCommit {
        let sha: String
        let date: Date
    }

    private struct CommitResponse: Decodable {
        struct Commit: Decodable {
            struct Signature: Decodable { let date: String }
            let committer: Signature
        }

        let sha: String
        let commit: Commit
    }

    private enum CheckError: LocalizedError {
        case badResponse(Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub ответил кодом \(code)."
            case .malformed: return "Ответ GitHub не удалось разобрать."
            }
        }
    }

    private static func fetchLatestCommit(using session: URLSession) async throws -> LatestCommit {
        var request = URLRequest(url: UpdatePolicy.latestCommitURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Curty", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CheckError.badResponse(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CommitResponse.self, from: data)
        guard let date = parseDate(decoded.commit.committer.date) else { throw CheckError.malformed }
        return LatestCommit(sha: decoded.sha, date: date)
    }

    private static func parseDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
