import AppKit
import Foundation

/// Seek is the only media command that carries a value, so the value can never
/// be allowed to reach the script as anything but bare digits: clamped to the
/// track, and formatted without a locale so a Russian system cannot turn the
/// separator into a comma the way it does for `player position as text`.
enum MediaSeekPolicy {
    static func clamp(_ seconds: Double, duration: Double) -> Double {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, seconds), duration)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0.000" }
        return String(format: "%.3f", seconds)
    }
}

/// Оба плеера принимают целое 0…100. Отдельная политика, потому что значение
/// приходит и снаружи — от чужого приложения, и изнутри — от пальца на ползунке.
enum MediaVolumePolicy {
    static let range: ClosedRange<Double> = 0...100

    static func clamp(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Плеер, который не сообщил громкость, отдаёт -1: ползунок в этом случае
    /// не показывается вовсе, вместо того чтобы показывать выдуманный ноль.
    static func reported(_ value: Double) -> Double? {
        value < 0 ? nil : clamp(value)
    }

    /// Целое без разделителя: дробь с запятой AppleScript в чужой локали
    /// прочитает не так, на этом уже обжигались с позицией трека.
    static func format(_ value: Double) -> String {
        String(Int(clamp(value).rounded()))
    }
}

/// Какие команды меняют состояние на экране сразу, не дожидаясь опроса.
/// Плеер отвечает не мгновенно, а опрос идёт раз в секунду: без этого значок
/// паузы менялся с задержкой до секунды, человек считал, что промахнулся, и
/// жал второй раз — возвращая всё обратно.
enum MediaOptimisticPolicy {
    static func applying(_ command: MediaCommand, to snapshot: MediaSnapshot?) -> MediaSnapshot? {
        guard command == .togglePlayPause, var updated = snapshot else { return nil }
        updated.isPlaying.toggle()
        return updated
    }
}

private enum PlayerKind: CaseIterable {
    case spotify
    case music

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    var durationDivisor: Double { self == .spotify ? 1_000 : 1 }

    /// Only Spotify publishes a cover link; Music deprecated its equivalent and
    /// leaves the field empty.
    private var artworkExpression: String {
        self == .spotify ? "artwork url of currentItem as text" : "\"\""
    }

    var snapshotScript: String {
        """
        tell application id "\(bundleID)"
            set separatorCharacter to ASCII character 30
            set currentItem to current track
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to "0"
            set trackArtwork to ""
            set playerVolume to "-1"
            try
                set playerVolume to (sound volume as text)
            end try
            try
                set trackName to name of currentItem as text
            end try
            try
                set trackArtist to artist of currentItem as text
            end try
            try
                set trackAlbum to album of currentItem as text
            end try
            try
                set trackDuration to duration of currentItem as text
            end try
            try
                set trackArtwork to \(artworkExpression)
            end try
            return (player state as text) & separatorCharacter & trackName & separatorCharacter & trackArtist & separatorCharacter & trackAlbum & separatorCharacter & trackDuration & separatorCharacter & (player position as text) & separatorCharacter & trackArtwork & separatorCharacter & playerVolume
        end tell
        """
    }

    /// Громкость самого плеера, а не системная: крутить общий звук машины
    /// ради музыки никто не просил, и это потребовало бы прав на System Events.
    func volumeScript(_ value: Double) -> String {
        """
        tell application id "\(bundleID)"
            set sound volume to \(MediaVolumePolicy.format(value))
        end tell
        """
    }

    func seekScript(toSeconds seconds: Double) -> String {
        """
        tell application id "\(bundleID)"
            set player position to \(MediaSeekPolicy.format(seconds))
        end tell
        """
    }

    func commandScript(_ command: MediaCommand) -> String {
        let body: String
        switch command {
        case .togglePlayPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = self == .music ? "back track" : "previous track"
        }
        return """
        tell application id "\(bundleID)"
            \(body)
        end tell
        """
    }
}

private final class FixedAppleScriptMediaAdapter: @unchecked Sendable {
    private typealias Candidate = (player: PlayerKind, snapshot: MediaSnapshot)

    /// An Apple Event sent to an app that is not running launches it. Curty
    /// polls once a second, so without this check closing Music simply started
    /// it again a second later. Nothing may be asked of a player that is not
    /// already there.
    private func isRunning(_ player: PlayerKind) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    func snapshot() throws -> MediaSnapshot? {
        let candidates = try collectCandidates()
        return candidates.first(where: { $0.snapshot.isPlaying })?.snapshot ?? candidates.first?.snapshot
    }

    /// Плеер известен из последнего снимка, поэтому команда стоит одного
    /// скрипта. Раньше каждое нажатие сначала опрашивало оба плеера заново —
    /// три обращения вместо одного, и все они могли повиснуть.
    func perform(_ command: MediaCommand, on source: String) throws {
        _ = try execute(try target(source).commandScript(command))
    }

    func seek(to seconds: Double, on source: String) throws {
        _ = try execute(try target(source).seekScript(toSeconds: seconds))
    }

    func setVolume(_ value: Double, on source: String) throws {
        _ = try execute(try target(source).volumeScript(value))
    }

    private func target(_ source: String) throws -> PlayerKind {
        guard let player = PlayerKind.allCases.first(where: { $0.displayName == source }),
              isRunning(player) else {
            throw AdapterError.noSupportedPlayer
        }
        return player
    }

    // Sending the event is what makes macOS show the Automation consent
    // prompt. AEDeterminePermissionToAutomateTarget looks like the polite way
    // to ask first, but it never returns for these targets: it blocks on an
    // internal semaphore, which wedged every later refresh behind isRefreshing.
    func requestAutomationAccess() throws {
        for player in PlayerKind.allCases where isRunning(player) {
            do {
                _ = try execute(player.snapshotScript)
                return
            } catch AdapterError.appleScript(let code) where code == -600 || code == -1_728 {
                continue
            }
        }
        throw AdapterError.noSupportedPlayer
    }

    private func collectCandidates() throws -> [Candidate] {
        var candidates: [Candidate] = []
        var firstError: Error?
        for player in PlayerKind.allCases {
            do {
                if let snapshot = try snapshot(for: player) {
                    candidates.append((player, snapshot))
                    if snapshot.isPlaying { return candidates }
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if candidates.isEmpty, let firstError { throw firstError }
        return candidates
    }

    private func snapshot(for player: PlayerKind) throws -> MediaSnapshot? {
        guard isRunning(player) else { return nil }

        let raw: String
        do {
            raw = try execute(player.snapshotScript)
        } catch AdapterError.appleScript(let code) where code == -1_728 || code == -600 {
            return nil
        }

        guard !raw.isEmpty else { return nil }
        let separator = Unicode.Scalar(30).map(String.init) ?? "\u{1E}"
        let parts = raw.components(separatedBy: separator)
        guard parts.count == 8, !parts[1].isEmpty else { return nil }
        return MediaSnapshot(
            source: player.displayName,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: parts[0].lowercased() == "playing",
            duration: Self.number(parts[4]) / player.durationDivisor,
            position: Self.number(parts[5]),
            artworkURL: parts[6],
            volume: MediaVolumePolicy.reported(Self.number(parts[7]))
        )
    }

    /// AppleScript renders reals with the current locale's decimal separator,
    /// so a Russian system returns "163,98" and plain Double(_:) yields nil.
    private static func number(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func execute(_ source: String) throws -> String {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, let code = error[NSAppleScript.errorNumber] as? Int, code != 0 {
            throw AdapterError.appleScript(code: code)
        }
        return descriptor?.stringValue ?? ""
    }

    enum AdapterError: LocalizedError {
        case noSupportedPlayer
        case appleScript(code: Int)

        var errorDescription: String? {
            switch self {
            case .noSupportedPlayer: return "Music и Spotify сейчас не запущены."
            case .appleScript(let code) where code == -1_744:
                return "Нужно один раз разрешить Curty управлять Spotify или Music."
            case .appleScript(let code) where code == -1_743:
                return "Разрешите Curty управлять Spotify или Music в Системных настройках → Конфиденциальность и безопасность → Автоматизация."
            case .appleScript(let code): return "macOS отклонила команду медиаплееру (\(code))."
            }
        }
    }
}

@MainActor
final class MediaStore: ObservableObject {
    @Published private(set) var snapshot: MediaSnapshot?
    /// Когда снимок сделан: между опросами ползунок досчитывает позицию сам,
    /// иначе он дёргается раз в секунду.
    @Published private(set) var snapshotAt = Date.distantPast
    @Published private(set) var isEnabled = false
    @Published private(set) var needsAutomationPermission = false
    @Published var lastError: String?

    private static let requestTimeout: TimeInterval = 6

    let artwork = ArtworkLoader()

    private let adapter = FixedAppleScriptMediaAdapter()
    /// Очередь последовательная: каждое обращение к плееру проходит через
    /// beginRequest, поэтому одновременных вызовов не бывает. Конкурентная
    /// очередь позволяла нажатиям «следующий трек» копить заблокированные
    /// потоки, пока плеер молчит, — и в пределе выносила пул GCD целиком.
    private let queue = DispatchQueue(label: "dev.curty.media", qos: .userInitiated)
    private var timer: Timer?
    private var isRefreshing = false
    private var requestStartedAt: TimeInterval = 0
    private var isUserRequestInFlight = false
    /// Уровень, к которому вернуться после снятия немоты.
    private var volumeBeforeMute: Double?
    private var generation = 0
    private var isPanelVisible = false

    func start() {
        guard !isEnabled else { return }
        generation += 1
        isEnabled = true
        updatePolling()
    }

    func stop() {
        generation += 1
        stopPolling()
        isRefreshing = false
        snapshot = nil
        artwork.clear()
        lastError = nil
        needsAutomationPermission = false
        isEnabled = false
    }

    /// Every snapshot costs an AppleScript round trip to Music and Spotify, and
    /// the result is only ever shown inside the panel. Polling therefore runs
    /// while the panel is on screen and stops as soon as it hides.
    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        updatePolling()
    }

    private func updatePolling() {
        if isEnabled, isPanelVisible {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// A script that never returns used to pin `isRefreshing` forever, which
    /// silently killed every later poll and left the panel on "Ищем трек…"
    /// until the app was restarted. Past the timeout the in-flight request is
    /// abandoned: its generation is retired so a late reply cannot land, and a
    /// fresh request takes over.
    /// Опрос идёт раз в секунду, и пока он в полёте, сторож молча отклонял
    /// нажатия: клик по дорожке просто пропадал — отсюда «не всегда
    /// перепрыгивает». Действие человека важнее фонового опроса и вытесняет
    /// его; ответ опроса отбрасывается по смене поколения. Друг друга действия
    /// не вытесняют: там остаётся прежняя защита по таймауту, чтобы зависший
    /// скрипт не собрал за собой очередь.
    #if DEBUG
    /// Правило вытеснения — причина исправленной жалобы, а не деталь: проверять
    /// его через живой AppleScript было бы нечем.
    func beginRequestForTesting(userInitiated: Bool) -> Bool {
        beginRequest(userInitiated: userInitiated)
    }
    #endif

    /// Умолчания у `userInitiated` нет намеренно. Оно тут было — и из-за него
    /// команды плеера годами уходили в канал как обычный опрос: нажатие,
    /// попавшее на секундный опрос, молча пропадало. Теперь каждый вызывающий
    /// обязан сказать, человек это или часы.
    private func beginRequest(userInitiated: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if isRefreshing {
            let preemptsPoll = userInitiated && !isUserRequestInFlight
            guard preemptsPoll || now - requestStartedAt >= Self.requestTimeout else { return false }
            generation += 1
        }
        isRefreshing = true
        isUserRequestInFlight = userInitiated
        requestStartedAt = now
        return true
    }

    func refresh() {
        guard isEnabled, beginRequest(userInitiated: false) else { return }
        let adapter = self.adapter
        let requestGeneration = generation
        queue.async { [weak self] in
            let result = Result { try adapter.snapshot() }
            Task { @MainActor in
                guard let self, self.generation == requestGeneration, self.isEnabled else { return }
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.snapshotAt = Date()
                    self.artwork.load(from: snapshot?.artworkURL ?? "")
                    self.lastError = nil
                    self.needsAutomationPermission = false
                case .failure(let error):
                    self.snapshot = nil
                    self.artwork.clear()
                    self.lastError = error.localizedDescription
                    self.needsAutomationPermission = Self.requiresAutomationPermission(error)
                }
            }
        }
    }

    func requestAutomationAccess() {
        guard isEnabled, beginRequest(userInitiated: false) else { return }
        let adapter = self.adapter
        let requestGeneration = generation
        queue.async { [weak self] in
            let result = Result { try adapter.requestAutomationAccess() }
            Task { @MainActor in
                guard let self, self.generation == requestGeneration, self.isEnabled else { return }
                self.isRefreshing = false
                switch result {
                case .success:
                    self.lastError = nil
                    self.needsAutomationPermission = false
                    self.refresh()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.needsAutomationPermission = Self.requiresAutomationPermission(error)
                }
            }
        }
    }

    // Команды проходят через тот же beginRequest, что и опрос. Раньше они шли в
    // очередь напрямую, и каждое нажатие по молчащему плееру добавляло ещё один
    // застрявший вызов — ровно тот отказ, от которого beginRequest и защищает.
    func perform(_ command: MediaCommand) {
        guard isEnabled, let source = snapshot?.source, beginRequest(userInitiated: true) else { return }

        // Состояние переключаем сразу, опрос через секунду подтвердит.
        if let optimistic = MediaOptimisticPolicy.applying(command, to: snapshot) {
            snapshot = optimistic
            // Отсчёт позиции начинается заново от текущей: без этого пауза
            // «доматывала» бы трек на время, пока он стоял.
            snapshotAt = Date()
        }
        let adapter = self.adapter
        let requestGeneration = generation
        queue.async { [weak self] in
            let result = Result { try adapter.perform(command, on: source) }
            Task { @MainActor in
                guard let self, self.generation == requestGeneration, self.isEnabled else { return }
                self.isRefreshing = false
                switch result {
                case .success:
                    self.lastError = nil
                    // Раньше здесь стоял немедленный опрос — и он часто
                    // возвращал позицию до перемотки, потому что плеер ещё не
                    // успел её применить: ползунок отскакивал назад. Обычный
                    // опрос через секунду подтвердит и так.
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Немота — это громкость 0 с запомненным уровнем: у плееров нет
    /// отдельного признака, а гасить системный звук мы не вправе.
    func toggleMute() {
        guard let volume = snapshot?.volume else { return }
        if volume > 0 {
            volumeBeforeMute = volume
            setVolume(0)
        } else {
            // Плеер могли заглушить и мимо Curty — тогда возвращать не к чему,
            // и половина громкости лучше, чем тишина в ответ на нажатие.
            setVolume(volumeBeforeMute ?? 50)
            volumeBeforeMute = nil
        }
    }

    func setVolume(_ value: Double) {
        guard isEnabled, let current = snapshot, current.volume != nil, beginRequest(userInitiated: true) else { return }
        let target = MediaVolumePolicy.clamp(value)
        // Ползунок встаёт сразу; следующий опрос через секунду это подтвердит.
        snapshot?.volume = target
        let adapter = self.adapter
        let source = current.source
        let requestGeneration = generation
        queue.async { [weak self] in
            let result = Result { try adapter.setVolume(target, on: source) }
            Task { @MainActor in
                guard let self, self.generation == requestGeneration, self.isEnabled else { return }
                self.isRefreshing = false
                switch result {
                case .success:
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func seek(to seconds: Double) {
        guard isEnabled, let current = snapshot, current.duration > 0, beginRequest(userInitiated: true) else { return }
        let target = MediaSeekPolicy.clamp(seconds, duration: current.duration)
        // Move the scrubber right away; the next poll confirms it a second later.
        snapshot?.position = target
        // Вместе с позицией сдвигается и точка отсчёта: без неё интерполяция
        // между опросами добавила бы к новой позиции время, прошедшее с
        // прошлого ответа, и ползунок уехал бы дальше места клика.
        snapshotAt = Date()
        let adapter = self.adapter
        let source = current.source
        let requestGeneration = generation
        queue.async { [weak self] in
            let result = Result { try adapter.seek(to: target, on: source) }
            Task { @MainActor in
                guard let self, self.generation == requestGeneration, self.isEnabled else { return }
                self.isRefreshing = false
                switch result {
                case .success:
                    self.lastError = nil
                    // Раньше здесь стоял немедленный опрос — и он часто
                    // возвращал позицию до перемотки, потому что плеер ещё не
                    // успел её применить: ползунок отскакивал назад. Обычный
                    // опрос через секунду подтвердит и так.
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private static func requiresAutomationPermission(_ error: Error) -> Bool {
        guard case let FixedAppleScriptMediaAdapter.AdapterError.appleScript(code) = error else {
            return false
        }
        return code == -1_743 || code == -1_744
    }
}
