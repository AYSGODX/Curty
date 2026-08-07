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

    /// Путь подставляется в скрипт, который выполнит Терминал, поэтому он
    /// закрывается одинарными кавычками целиком — пробел или апостроф в имени
    /// папки иначе разорвал бы команду.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func updateScript(repositoryPath: String) -> String {
        """
        #!/bin/bash
        set -euo pipefail

        REPO=\(shellQuoted(repositoryPath))

        echo "Обновление Curty"
        echo "Репозиторий: $REPO"
        echo

        if [ ! -d "$REPO/.git" ]; then
            echo "Репозиторий не найден по этому пути." >&2
            echo "Склонируйте его заново и запустите Scripts/install.sh:" >&2
            echo "  git clone https://github.com/\(repository).git" >&2
            exit 1
        fi

        cd "$REPO"
        git pull --ff-only
        bash Scripts/install.sh

        echo
        echo "Готово. Окно можно закрыть."
        """
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateState = .unknown

    /// Вшивается в Info.plist сборкой: без этих трёх значений сравнивать не с
    /// чем и обновлять нечего.
    let buildCommit: String?
    let buildDate: Date?
    private let repositoryPath: String?

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
        repositoryPath = (info?["CurtyRepositoryPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    var shortCommit: String? { buildCommit.map { String($0.prefix(7)) } }

    var canInstallUpdate: Bool {
        guard case .available = state else { return false }
        return repositoryPath != nil
    }

    /// Настройки открывают вкладку часто, а лимит GitHub для анонимных запросов
    /// — шестьдесят в час на адрес. Раз в полчаса более чем достаточно.
    func checkIfStale() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 30 * 60, state != .unknown { return }
        check()
    }

    func check() {
        guard state != .checking else { return }
        guard let buildCommit else {
            state = .failed("Сборка сделана вне git-репозитория, сравнивать не с чем.")
            return
        }

        state = .checking
        lastCheck = Date()
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

    func startUpdate() {
        guard let repositoryPath else {
            state = .failed("В сборке не записан путь к репозиторию. Обновите вручную: git pull && Scripts/install.sh")
            return
        }

        // Скрипт живёт в самом репозитории: так его видно и можно прочитать
        // до запуска. Терминал открывает его как обычный файл — запустить его
        // сама Curty не может, дочерний процесс унаследовал бы её песочницу и
        // не добрался бы ни до репозитория, ни до /Applications.
        let inRepository = URL(fileURLWithPath: repositoryPath)
            .appendingPathComponent("Scripts/update.command")
        if NSWorkspace.shared.open(inRepository) { return }

        // Запасной путь на случай, если песочница не отдаёт файл за пределами
        // контейнера: своя копия того же скрипта внутри него.
        let script = ApplicationPaths.supportDirectory.appendingPathComponent("update.command")
        do {
            try UpdatePolicy.updateScript(repositoryPath: repositoryPath).write(
                to: script,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            state = .failed("Не удалось подготовить обновление: \(error.localizedDescription)")
            return
        }

        // Терминал открывает скрипт как обычный файл: сама Curty запустить его
        // не может — дочерний процесс унаследовал бы её песочницу и не добрался
        // бы ни до репозитория, ни до /Applications.
        guard NSWorkspace.shared.open(script) else {
            state = .failed("Не удалось открыть Терминал. Выполните вручную: cd \(repositoryPath) && git pull && Scripts/install.sh")
            return
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
