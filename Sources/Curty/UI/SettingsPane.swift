import SwiftUI

/// Settings render inside the panel rather than in a window of their own: a
/// window belongs to a Space, and activating the app to show it threw the user
/// onto whichever desktop that window happened to live on.
struct SettingsPane: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var preferences: Preferences
    @ObservedObject private var updates: UpdateChecker
    @State private var isConfirmingDeletion = false

    init(model: AppModel) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: model.preferences)
        _updates = ObservedObject(wrappedValue: model.updates)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                section("Интеграции") {
                    privacyToggle(
                        "История буфера обмена",
                        detail: "Включена по умолчанию; при необходимости её можно приостановить.",
                        isOn: $preferences.clipboardMonitoringEnabled
                    )
                    Divider()
                    privacyToggle(
                        "Показывать изображения в памяти",
                        detail: "Превью живут только в памяти; сохранение на полку всегда выполняется отдельно.",
                        isOn: $preferences.clipboardImagesEnabled,
                        isEnabled: preferences.clipboardMonitoringEnabled
                    )
                    Divider()
                    privacyToggle(
                        "Управление медиа",
                        detail: "Автоматически находит текущий трек в Music или Spotify.",
                        isOn: $preferences.mediaIntegrationEnabled
                    )
                }

                section("Приложение") {
                    SettingsToggleRow(
                        title: "Запускать при входе",
                        detail: "Управляется системным разделом «Объекты входа».",
                        isOn: Binding(
                            get: { preferences.launchAtLoginEnabled },
                            set: { preferences.setLaunchAtLogin(enabled: $0) }
                        ),
                        isEnabled: preferences.canChangeLaunchAtLogin,
                        stateLabel: preferences.launchAtLoginState.label,
                        stateStyle: preferences.launchAtLoginState.badgeStyle
                    )

                    if let message = preferences.launchAtLoginMessage {
                        Label(message, systemImage: preferences.launchAtLoginState == .requiresApproval
                              ? "exclamationmark.triangle.fill"
                              : "info.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(preferences.launchAtLoginState == .requiresApproval ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if preferences.launchAtLoginState == .requiresApproval {
                        Button("Открыть «Объекты входа»") {
                            preferences.openLoginItemsSettings()
                        }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                section("Время") {
                    timeZoneRow
                }

                section("Обновление") {
                    updateSection
                }

                section("Панель") {
                    SettingsToggleRow(
                        title: "Не мешать в полноэкранном режиме",
                        detail: "Пока игра, видео или презентация занимают весь экран, шторка не раскрывается.",
                        isOn: $preferences.respectFullScreenEnabled,
                        isEnabled: true,
                        stateLabel: preferences.respectFullScreenEnabled ? "Включено" : "Выключено",
                        stateStyle: preferences.respectFullScreenEnabled ? .active : .inactive
                    )
                    Divider()
                    Text("Иконки в левом столбце можно перетаскивать, чтобы поставить нужный инструмент первым.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Вернуть исходный порядок") { model.resetToolOrder() }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                section("Локальные данные") {
                    Text("Удаляет историю буфера, ссылки с полки, сниппеты и заметки с этого Mac.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Удалить все локальные данные") {
                        isConfirmingDeletion = true
                    }
                    .buttonStyle(CurtySecondaryButtonStyle(isDestructive: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 4)
        }
        .confirmationDialog(
            "Удалить все локальные данные?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Удалить", role: .destructive) { model.deleteAllLocalData() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История буфера, ссылки с полки, сниппеты и заметки будут стёрты. Это нельзя отменить.")
        }
    }

    private var timeZoneRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Показывать время в поясе")
                    .font(.system(size: 12, weight: .medium))
                Text("Пригодится, если часы на маке не совпадают с местом, где вы находитесь. По умолчанию Curty берёт пояс системы.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Menu(timeZoneLabel) {
                Button("Системный — \(DisplayTimeZonePolicy.cityName(TimeZone.current.identifier))") {
                    preferences.displayTimeZoneIdentifier = ""
                }
                Divider()
                // Плоский список из шестисот поясов в меню шторки не помещается,
                // поэтому он разбит по частям света.
                ForEach(DisplayTimeZonePolicy.groupedIdentifiers, id: \.region) { group in
                    Menu(group.region) {
                        ForEach(group.identifiers, id: \.self) { identifier in
                            Button(DisplayTimeZonePolicy.cityName(identifier)) {
                                preferences.displayTimeZoneIdentifier = identifier
                            }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)
        }
    }

    private var timeZoneLabel: String {
        preferences.displayTimeZoneIdentifier.isEmpty
            ? "Системный"
            : DisplayTimeZonePolicy.cityName(preferences.displayTimeZoneIdentifier)
    }

    @ViewBuilder
    private var updateSection: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Установленная версия")
                    .font(.system(size: 12, weight: .medium))
                Text(buildDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(updateStatus.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(updateStatus.style.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(updateStatus.style.color.opacity(0.12), in: Capsule())
        }

        if case .failed(let message) = updates.state {
            CurtyErrorRow(message: message)
        }

        HStack(spacing: 8) {
            // Кнопка не гаснет совсем, а тускнеет: исчезающий элемент читается
            // как поломка, а выключенный — как «пока нечего ставить».
            Button("Обновить") {
                // Шторка висит поверх всего, включая окно Терминала и любые
                // системные диалоги: оставить её открытой значит спрятать от
                // человека всё, что происходит дальше.
                if updates.startUpdate() { model.requestPanelClose() }
            }
                .buttonStyle(CurtyProminentButtonStyle())
                .disabled(!updates.canInstallUpdate)

            Button(updates.state == .checking ? "Проверяю…" : "Проверить") { updates.check() }
                .buttonStyle(CurtySecondaryButtonStyle())
                .disabled(updates.state == .checking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Text("Обновление откроет Терминал: он заберёт свежую версию с GitHub, пересоберёт её и перезапустит Curty. Заметки, сниппеты, полка и настройки останутся на месте.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buildDescription: String {
        guard let commit = updates.shortCommit else {
            return "Собрана вне git-репозитория — проверка недоступна."
        }
        guard let date = updates.buildDate else { return "Сборка \(commit)" }
        return "Сборка \(commit) от \(Self.dateFormatter.string(from: date))"
    }

    private var updateStatus: (label: String, style: SettingsToggleBadgeStyle) {
        switch updates.state {
        case .unknown: ("Не проверялось", .unavailable)
        case .checking: ("Проверяю…", .inactive)
        case .upToDate: ("Последняя", .active)
        case .available(_, let date): ("Есть от \(Self.dateFormatter.string(from: date))", .warning)
        case .failed: ("Ошибка", .warning)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            CurtyCard {
                VStack(spacing: 8) { content() }
            }
        }
    }

    private func privacyToggle(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        SettingsToggleRow(
            title: title,
            detail: detail,
            isOn: isOn,
            isEnabled: isEnabled,
            stateLabel: isEnabled ? (isOn.wrappedValue ? "Включено" : "Выключено") : "Недоступно",
            stateStyle: isEnabled ? (isOn.wrappedValue ? .active : .inactive) : .unavailable
        )
    }
}

private extension LaunchAtLoginState {
    var badgeStyle: SettingsToggleBadgeStyle {
        switch self {
        case .enabled: .active
        case .disabled: .inactive
        case .requiresApproval: .warning
        case .unavailable: .unavailable
        }
    }
}

private enum SettingsToggleBadgeStyle {
    case active
    case inactive
    case warning
    case unavailable

    var color: Color {
        switch self {
        case .active: CurtyTheme.accent
        case .warning: .orange
        case .inactive, .unavailable: .secondary
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    let stateLabel: String
    let stateStyle: SettingsToggleBadgeStyle

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(stateLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(stateStyle.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(stateStyle.color.opacity(0.12), in: Capsule())
                .contentTransition(.numericText())

            CurtySwitch(isOn: $isOn, isEnabled: isEnabled)
        }
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .animation(.easeInOut(duration: 0.16), value: stateLabel)
    }
}
