import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var label: String {
        switch self {
        case .disabled: "Выключено"
        case .enabled: "Включено"
        case .requiresApproval: "Нужно разрешение"
        case .unavailable: "Нужно установить"
        }
    }
}

enum LaunchAtLoginPolicy {
    /// Спрашиваем ровно один раз и только когда есть о чём: если автозапуск уже
    /// включён или включить его на этой машине нельзя, вопрос лишний.
    static func shouldAsk(alreadyAsked: Bool, isEnabled: Bool, canChange: Bool) -> Bool {
        !alreadyAsked && !isEnabled && canChange
    }

    static func isInApplicationsFolder(
        bundleURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true).path + "/"
        let userApplications = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path + "/"
        return path.hasPrefix(systemApplications) || path.hasPrefix(userApplications)
    }

    static func installationMessage() -> String {
        "Чтобы включить автозапуск, переместите Curty.app в папку «Программы» и откройте приложение оттуда."
    }

    static func friendlyMessage(for error: Error, bundleURL: URL) -> String {
        guard isInApplicationsFolder(bundleURL: bundleURL) else {
            return installationMessage()
        }

        let nsError = error as NSError
        if nsError.code == 3 {
            return "macOS не приняла подпись этой сборки Curty. Соберите подписанную версию приложения и попробуйте снова."
        }
        if nsError.code == 12 {
            return "macOS ждёт вашего разрешения. Откройте «Объекты входа» и разрешите запуск Curty."
        }
        return "macOS не смогла изменить автозапуск Curty. Откройте «Объекты входа» и проверьте разрешение приложения."
    }
}

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let clipboardMonitoring = "privacy.clipboardMonitoring"
        static let clipboardImages = "privacy.clipboardImages"
        static let mediaIntegration = "privacy.mediaIntegration"
        static let toolOrder = "layout.toolOrder"
        static let respectFullScreen = "layout.respectFullScreen"
        static let displayTimeZone = "layout.displayTimeZone"
        static let calendarWasGranted = "calendar.wasGranted"
        static let launchAtLoginAsked = "app.launchAtLoginAsked"
        static let translateSource = "translate.source"
        static let translateTarget = "translate.target"
    }

    private let defaults: UserDefaults
    private let bundleURL: URL

    @Published var clipboardMonitoringEnabled: Bool {
        didSet { defaults.set(clipboardMonitoringEnabled, forKey: Key.clipboardMonitoring) }
    }

    @Published var clipboardImagesEnabled: Bool {
        didSet { defaults.set(clipboardImagesEnabled, forKey: Key.clipboardImages) }
    }

    @Published var mediaIntegrationEnabled: Bool {
        didSet { defaults.set(mediaIntegrationEnabled, forKey: Key.mediaIntegration) }
    }

    /// Пока приложение развёрнуто на весь экран — игра, презентация, видео —
    /// шторка не раскрывается: курсор к верхней кромке там ходит по делу.
    @Published var respectFullScreenEnabled: Bool {
        didSet { defaults.set(respectFullScreenEnabled, forKey: Key.respectFullScreen) }
    }

    /// Языки переводчика. Пустой источник — «определять по тексту».
    @Published var translateSourceCode: String {
        didSet { defaults.set(translateSourceCode, forKey: Key.translateSource) }
    }

    @Published var translateTargetCode: String {
        didSet { defaults.set(translateTargetCode, forKey: Key.translateTarget) }
    }

    /// Про автозапуск уже спрашивали. Прописываться в объекты входа без спроса
    /// невежливо, а молчать — значит оставить человека после перезагрузки без
    /// приложения, которое macOS даже не показывает в поиске: приложения-агенты
    /// она не индексирует. Поэтому спрашиваем ровно один раз.
    @Published var launchAtLoginAsked: Bool {
        didSet { defaults.set(launchAtLoginAsked, forKey: Key.launchAtLoginAsked) }
    }

    /// Доступ к календарю однажды выдавали. Нужно, чтобы отличить «ещё не
    /// просили» от «сбросилось после обновления»: для человека это очень
    /// разные вещи, а система в обоих случаях отвечает одинаково.
    @Published var calendarAccessWasGranted: Bool {
        didSet { defaults.set(calendarAccessWasGranted, forKey: Key.calendarWasGranted) }
    }

    /// Идентификатор пояса, в котором показывать время. Пустая строка —
    /// системный, и это умолчание: у всех, кто настройку не трогал, ничего
    /// не меняется.
    @Published var displayTimeZoneIdentifier: String {
        didSet { defaults.set(displayTimeZoneIdentifier, forKey: Key.displayTimeZone) }
    }

    var displayTimeZone: TimeZone { DisplayTimeZonePolicy.resolve(identifier: displayTimeZoneIdentifier) }

    var isDisplayTimeZoneOverridden: Bool {
        DisplayTimeZonePolicy.isOverridden(identifier: displayTimeZoneIdentifier)
    }

    /// Raw values of the rail tools in the user's own order. Empty means "never
    /// rearranged", which resolves to the natural order.
    @Published var toolOrder: [String] {
        didSet { defaults.set(toolOrder, forKey: Key.toolOrder) }
    }

    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled
    @Published private(set) var launchAtLoginMessage: String?

    var launchAtLoginEnabled: Bool {
        launchAtLoginState == .enabled || launchAtLoginState == .requiresApproval
    }

    var canChangeLaunchAtLogin: Bool {
        launchAtLoginState != .unavailable
    }

    init(
        defaults: UserDefaults = .standard,
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        self.defaults = defaults
        self.bundleURL = bundleURL
        defaults.register(defaults: [
            Key.clipboardMonitoring: true,
            Key.clipboardImages: false,
            Key.mediaIntegration: true,
            Key.respectFullScreen: true,
        ])
        clipboardMonitoringEnabled = defaults.bool(forKey: Key.clipboardMonitoring)
        clipboardImagesEnabled = defaults.bool(forKey: Key.clipboardImages)
        mediaIntegrationEnabled = defaults.bool(forKey: Key.mediaIntegration)
        respectFullScreenEnabled = defaults.bool(forKey: Key.respectFullScreen)
        displayTimeZoneIdentifier = defaults.string(forKey: Key.displayTimeZone) ?? ""
        calendarAccessWasGranted = defaults.bool(forKey: Key.calendarWasGranted)
        launchAtLoginAsked = defaults.bool(forKey: Key.launchAtLoginAsked)
        translateSourceCode = defaults.string(forKey: Key.translateSource) ?? ""
        // По умолчанию переводим на язык системы: чаще всего человек вставляет
        // чужой текст, чтобы прочитать его на своём.
        translateTargetCode = defaults.string(forKey: Key.translateTarget)
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        toolOrder = defaults.stringArray(forKey: Key.toolOrder) ?? []
        refreshLaunchAtLogin()
    }

    /// Спрашивать больше не о чем, если человек уже включил автозапуск сам,
    /// если ответил на вопрос, или если включить его на этой машине нельзя.
    var shouldAskAboutLaunchAtLogin: Bool {
        LaunchAtLoginPolicy.shouldAsk(
            alreadyAsked: launchAtLoginAsked,
            isEnabled: launchAtLoginEnabled,
            canChange: canChangeLaunchAtLogin
        )
    }

    func setLaunchAtLogin(enabled: Bool) {
        // Переключили руками — ответ получен, спрашивать незачем.
        launchAtLoginAsked = true
        launchAtLoginMessage = nil

        if enabled,
           !LaunchAtLoginPolicy.isInApplicationsFolder(bundleURL: bundleURL),
           SMAppService.mainApp.status != .enabled,
           SMAppService.mainApp.status != .requiresApproval {
            launchAtLoginState = .unavailable
            launchAtLoginMessage = LaunchAtLoginPolicy.installationMessage()
            return
        }

        do {
            let status = SMAppService.mainApp.status
            if enabled {
                if status == .notRegistered || status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } else if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginMessage = LaunchAtLoginPolicy.friendlyMessage(
                for: error,
                bundleURL: bundleURL
            )
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginState = .enabled
        case .requiresApproval:
            launchAtLoginState = .requiresApproval
            if launchAtLoginMessage == nil {
                launchAtLoginMessage = "Разрешите Curty в «Системные настройки» → «Основные» → «Объекты входа»."
            }
        case .notFound:
            launchAtLoginState = .unavailable
            if launchAtLoginMessage == nil {
                launchAtLoginMessage = "macOS не нашла приложение Curty для автозапуска. Переместите его в папку «Программы»."
            }
        case .notRegistered:
            if LaunchAtLoginPolicy.isInApplicationsFolder(bundleURL: bundleURL) {
                launchAtLoginState = .disabled
            } else {
                launchAtLoginState = .unavailable
                if launchAtLoginMessage == nil {
                    launchAtLoginMessage = LaunchAtLoginPolicy.installationMessage()
                }
            }
        @unknown default:
            launchAtLoginState = .unavailable
            if launchAtLoginMessage == nil {
                launchAtLoginMessage = "Эта версия macOS не сообщила состояние автозапуска Curty."
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
