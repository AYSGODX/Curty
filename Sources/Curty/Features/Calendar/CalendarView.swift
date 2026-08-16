import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @ObservedObject var preferences: Preferences
    let onHandOff: () -> Void

    private var zone: TimeZone { preferences.displayTimeZone }

    @State private var hoveredHorizon: CalendarStore.Horizon?

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
                            .foregroundStyle(CurtyTheme.engravedDim)
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
                // Система одинаково отвечает «не спрашивали» и когда доступ
                // никогда не выдавали, и когда его сбросило обновление. Для
                // человека это разные вещи: во втором случае кнопка выглядит
                // так, будто настройка слетела сама.
                accessCard(
                    title: preferences.calendarAccessWasGranted
                        ? "Доступ к календарю сбросился"
                        : "Доступ к календарю выключен",
                    detail: preferences.calendarAccessWasGranted
                        ? "Так бывает после обновления: macOS считает пересобранное приложение новым. Выдайте разрешение заново."
                        : "Curty запросит разрешение только по вашей команде.",
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
                DrawnEmptyState(
                    icon: "calendar.badge.checkmark",
                    title: "Встреч нет",
                    detail: store.horizon.emptyDetail
                )

                // Пустой список читается как «календарь не работает», хотя чаще
                // всего нужная учётная запись просто не подключена к системе.
                // Curty берёт события из всех календарей сразу.
                CurtyCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Не хватает календаря?")
                            .font(.system(size: 12, weight: .medium))
                        Text("Curty показывает все календари, подключённые к системному «Календарю» — Google, Exchange, iCloud. Отдельный вход в Curty не нужен: аккаунт добавляется один раз в настройках системы.")
                            .font(.caption2)
                            .foregroundStyle(CurtyTheme.engravedDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Учётные записи интернета") {
                            store.openAccountSettings()
                            onHandOff()
                        }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .curtyHoverLift()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                CurtyListPane(footer: "встреч \(meetings.count)") {
                    LazyVStack(spacing: 5) {
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
                                            .foregroundStyle(CurtyTheme.engravedDim)
                                    }
                                }
                                .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(meeting.provider ?? meeting.calendarName)
                                        .font(.caption2)
                                        .foregroundStyle(CurtyTheme.engravedDim)
                                }
                                Spacer()
                                if meeting.link != nil {
                                    Button("Войти") { store.join(meeting) }
                                        .buttonStyle(CurtySecondaryButtonStyle())
                                        .curtyHoverLift()
                                }
                            }
                            .padding(9)
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .foregroundStyle(tint(for: option))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(background(for: option))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            hoveredHorizon = option
                        } else if hoveredHorizon == option {
                            hoveredHorizon = nil
                        }
                    }
                }
                .accessibilityLabel(option.title)
            }
        }
        .padding(2)
        .frame(width: 148)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }

    private func tint(for option: CalendarStore.Horizon) -> Color {
        if store.horizon == option { return Color(red: 0.13, green: 0.10, blue: 0.03) }
        return hoveredHorizon == option ? CurtyTheme.engraved : CurtyTheme.engravedDim
    }

    private func background(for option: CalendarStore.Horizon) -> Color {
        if store.horizon == option { return CurtyTheme.accent }
        return hoveredHorizon == option ? Color.white.opacity(0.08) : .clear
    }

    private func accessCard(
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        CurtySection(title: title, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionTitle, action: action)
                    .buttonStyle(CurtyProminentButtonStyle())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
