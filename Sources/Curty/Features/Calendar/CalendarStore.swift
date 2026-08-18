import AppKit
import EventKit

struct MeetingSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarName: String
    let link: URL?

    var provider: String? { link.flatMap(MeetingURLPolicy.provider) }
}

@MainActor
final class CalendarStore: ObservableObject {
    enum AuthorizationState: Equatable {
        case notRequested
        case granted
        case denied
    }

    enum Horizon: String, CaseIterable, Identifiable {
        case day
        case week

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "Сутки"
            case .week: return "Неделя"
            }
        }

        var heading: String {
            switch self {
            case .day: return "Сегодня"
            case .week: return "Ближайшая неделя"
            }
        }

        var emptyDetail: String {
            switch self {
            case .day: return "Показаны следующие 24 часа"
            case .week: return "Показаны следующие 7 дней"
            }
        }

        var duration: TimeInterval {
            switch self {
            case .day: return 24 * 60 * 60
            case .week: return 7 * 24 * 60 * 60
            }
        }

        var limit: Int {
            switch self {
            case .day: return 12
            case .week: return 40
            }
        }
    }

    @Published private(set) var authorization: AuthorizationState = .notRequested
    @Published private(set) var meetings: [MeetingSummary] = []
    @Published var lastError: String?
    @Published var horizon: Horizon = .day {
        didSet {
            guard horizon != oldValue else { return }
            reload()
        }
    }

    private let eventStore: EKEventStore
    private let fetcher: CalendarFetchAdapter
    private var observer: NSObjectProtocol?
    private var reloadTask: Task<Void, Never>?
    private var changeDebounce: Task<Void, Never>?

    init() {
        let store = EKEventStore()
        eventStore = store
        fetcher = CalendarFetchAdapter(store: store)
        refreshAuthorization()
    }

    /// Пока системный запрос на экране, панель должна уступить ему уровень.
    var onPermissionPromptChange: ((Bool) -> Void)?

    func refreshAuthorization() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorization = .granted
            installObserverIfNeeded()
            reload()
        case .notDetermined:
            authorization = .notRequested
        default:
            authorization = .denied
        }
    }

    func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            refreshAuthorization()
            return
        }
        // Панель висит на уровне строки меню, то есть выше системного запроса:
        // без этого диалог о доступе к календарю открывался под шторкой, и
        // человек видел только то, что ничего не происходит.
        onPermissionPromptChange?(true)
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.onPermissionPromptChange?(false)
                if let error { self.lastError = error.localizedDescription }
                self.authorization = granted ? .granted : .denied
                if granted {
                    self.installObserverIfNeeded()
                    self.reload()
                }
            }
        }
    }

    /// Список — снимок на момент загрузки, а время идёт: встреча, которая
    /// закончилась пять минут назад, продолжала висеть первой строкой. Отбор
    /// вынесен отдельно, чтобы вьюха могла пересчитывать его по часам, не
    /// трогая хранилище. Идущая сейчас встреча остаётся: она не прошедшая, и
    /// ссылка на неё нужна именно в этот момент.
    static func upcoming(_ meetings: [MeetingSummary], now: Date) -> [MeetingSummary] {
        meetings.filter { $0.end > now }
    }

    /// У повторяющейся встречи все повторения делят один eventIdentifier —
    /// это идентификатор серии, а не события. Списку нужны различимые:
    /// ForEach с одинаковыми id теряет строки, и из пяти ежедневных
    /// стендапов на неделе был виден один.
    nonisolated static func occurrenceID(identifier: String?, start: Date) -> String {
        guard let identifier else { return UUID().uuidString }
        return "\(identifier)@\(start.timeIntervalSinceReferenceDate)"
    }

    /// Запрос к EventKit — документированно долгий синхронный вызов, а
    /// перезагрузка привязана к каждому раскрытию шторки: на машине с парой
    /// аккаунтов и сотнями событий он задерживал её первый кадр. Поэтому сам
    /// запрос уходит с главного потока, а список меняется по его ответу —
    /// и только если за это время не запросили новее. Прежний список до
    /// ответа остаётся на экране: пустота на долю секунды читалась бы как
    /// «встречи пропали».
    func reload() {
        guard authorization == .granted else { return }
        lastError = nil
        let start = Date()
        let end = start.addingTimeInterval(horizon.duration)
        let limit = horizon.limit
        let fetcher = fetcher
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let fetched = await Task.detached(priority: .userInitiated) {
                fetcher.fetch(start: start, end: end, limit: limit)
            }.value
            guard !Task.isCancelled else { return }
            self?.meetings = fetched
        }
    }

    func join(_ meeting: MeetingSummary) {
        guard let link = meeting.link, MeetingURLPolicy.validate(link) != nil else { return }
        NSWorkspace.shared.open(link)
    }

    /// Google, Exchange и прочие сервисы попадают в Curty через системный
    /// «Календарь»: события читаются из всех календарей сразу, отдельного
    /// входа в каждый сервис не нужно. Узнать об этом человеку неоткуда,
    /// поэтому из пустого состояния ведём прямо в нужный раздел настроек.
    func openAccountSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private func installObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReloadAfterStoreChange() }
        }
    }

    /// Во время синхронизации аккаунтов уведомления о смене хранилища сыплются
    /// пачками — пачка собирается в один перезапрос, а не в десять подряд.
    private func scheduleReloadAfterStoreChange() {
        changeDebounce?.cancel()
        changeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

/// Выполняет запрос EventKit вне главного потока. EKEventStore не помечен
/// Sendable, но его вызовы потокобезопасны — тот же приём, что
/// FixedAppleScriptMediaAdapter у медиа. Объекты EKEvent за пределы потока
/// не выносятся: наружу уходят только значения MeetingSummary.
private final class CalendarFetchAdapter: @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func fetch(start: Date, end: Date, limit: Int) -> [MeetingSummary] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { event in
                MeetingSummary(
                    id: CalendarStore.occurrenceID(identifier: event.eventIdentifier, start: event.startDate),
                    title: event.title ?? "Без названия",
                    start: event.startDate,
                    end: event.endDate,
                    calendarName: event.calendar.title,
                    link: Self.approvedLink(for: event)
                )
            }
    }

    private static func approvedLink(for event: EKEvent) -> URL? {
        let candidates = [event.location, event.notes, event.url?.absoluteString].compactMap { $0 }
        return candidates.lazy.compactMap(MeetingURLPolicy.firstApprovedURL).first
    }
}
