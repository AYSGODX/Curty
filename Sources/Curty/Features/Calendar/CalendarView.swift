import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var preferences: Preferences
    let onHandOff: () -> Void

    private var zone: TimeZone { preferences.displayTimeZone }

    var body: some View {
        VStack(spacing: 10) {
            if let error = store.lastError {
                CurtyErrorRow(message: error) { store.lastError = nil }
            }
            CurtyCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.horizon.heading)
                            .font(.system(size: 15, weight: .semibold))
                        Text(Date.now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Пояс отличается от системного: без этой строки 19:00
                        // в Curty против 15:00 в «Календаре» читается как сбой.
                        if preferences.isDisplayTimeZoneOverridden {
                            Text("Время по \(DisplayTimeZonePolicy.cityName(zone.identifier))")
                                .font(.caption2)
                                .foregroundStyle(CurtyTheme.accent)
                        }
                    }
                    Spacer()
                    horizonSwitcher
                }
            }
            switch store.authorization {
            case .notRequested:
                accessCard(
                    title: "Доступ к календарю выключен",
                    detail: "Curty запросит разрешение только по вашей команде.",
                    actionTitle: "Подключить календарь",
                    action: store.requestAccess
                )
            case .denied:
                accessCard(
                    title: "Доступ к календарю запрещён",
                    detail: "Разрешение можно изменить в Системных настройках.",
                    actionTitle: "Открыть настройки приватности",
                    action: store.openPrivacySettings
                )
            case .granted:
                // Пересчёт по часам: пока панель открыта, закончившиеся встречи
                // должны уходить из списка сами.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    granted(now: context.date)
                }
            }
        }
    }

    @ViewBuilder
    private func granted(now: Date) -> some View {
        let meetings = CalendarStore.upcoming(store.meetings, now: now)
        VStack(spacing: 10) {
            if meetings.isEmpty {
                CurtyCard {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(CurtyTheme.success)
                        Text("Ближайших встреч нет")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.horizon.emptyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                }

                // Пустой список читается как «календарь не работает», хотя чаще
                // всего нужная учётная запись просто не подключена к системе.
                // Curty берёт события из всех календарей сразу.
                CurtyCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Не хватает календаря?")
                            .font(.system(size: 12, weight: .medium))
                        Text("Curty показывает все календари, подключённые к системному «Календарю» — Google, Exchange, iCloud. Отдельный вход в Curty не нужен: аккаунт добавляется один раз в настройках системы.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Учётные записи интернета") {
                            store.openAccountSettings()
                            onHandOff()
                        }
                        .buttonStyle(CurtySecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(meetings) { meeting in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(meeting.start.formatted(Date.FormatStyle(time: .shortened, timeZone: zone)))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(CurtyTheme.accent)
                                    // In week mode the time alone is ambiguous.
                                    if !DisplayTimeZonePolicy.calendar(for: zone).isDateInToday(meeting.start) {
                                        Text(meeting.start.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day()))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(meeting.provider ?? meeting.calendarName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if meeting.link != nil {
                                    Button("Войти") { store.join(meeting) }
                                        .buttonStyle(CurtySecondaryButtonStyle())
                                }
                            }
                            .padding(9)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
            }
        }
    }

    private var horizonSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(CalendarStore.Horizon.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { store.horizon = option }
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(store.horizon == option ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(store.horizon == option ? CurtyTheme.accent : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
            }
        }
        .padding(2)
        .frame(width: 148)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(0.07))
        )
    }

    private func accessCard(
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        CurtyCard {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(actionTitle, action: action)
                    .buttonStyle(CurtyProminentButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        }
    }
}
