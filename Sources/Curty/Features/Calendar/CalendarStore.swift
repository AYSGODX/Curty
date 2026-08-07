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

    private let eventStore = EKEventStore()
    private var observer: NSObjectProtocol?

    init() { refreshAuthorization() }

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

    func reload() {
        guard authorization == .granted else { return }
        let start = Date()
        let end = start.addingTimeInterval(horizon.duration)
        lastError = nil
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        meetings = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(horizon.limit)
            .map { event in
                MeetingSummary(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Без названия",
                    start: event.startDate,
                    end: event.endDate,
                    calendarName: event.calendar.title,
                    link: approvedLink(for: event)
                )
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

    private func approvedLink(for event: EKEvent) -> URL? {
        let candidates = [event.location, event.notes, event.url?.absoluteString].compactMap { $0 }
        return candidates.lazy.compactMap(MeetingURLPolicy.firstApprovedURL).first
    }

    private func installObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }
}
