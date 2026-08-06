import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var preferences: Preferences

    init(model: AppModel) {
        self.model = model
        _preferences = ObservedObject(wrappedValue: model.preferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CurtyTheme.accent.gradient)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Curty")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Настройки приложения")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)

            Divider()

            Form {
                Section("Интеграции") {
                    privacyToggle(
                        "История буфера обмена",
                        detail: "Включена по умолчанию; при необходимости её можно приостановить.",
                        isOn: $preferences.clipboardMonitoringEnabled
                    )
                    privacyToggle(
                        "Показывать изображения в памяти",
                        detail: "Превью живут только в памяти; сохранение на полку всегда выполняется отдельно.",
                        isOn: $preferences.clipboardImagesEnabled,
                        isEnabled: preferences.clipboardMonitoringEnabled
                    )
                    privacyToggle(
                        "Управление медиа",
                        detail: "Автоматически находит текущий трек в Music или Spotify.",
                        isOn: $preferences.mediaIntegrationEnabled
                    )
                }

                Section("Приложение") {
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
                            .font(.caption)
                            .foregroundStyle(preferences.launchAtLoginState == .requiresApproval ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if preferences.launchAtLoginState == .requiresApproval {
                        Button("Открыть «Объекты входа»") {
                            preferences.openLoginItemsSettings()
                        }
                    }
                }

                Section("Локальные данные") {
                    Button("Удалить все локальные данные", role: .destructive) {
                        model.deleteAllLocalData()
                    }
                    Text("Удаляет историю буфера, ссылки с полки, сниппеты и заметки с этого Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            preferences.refreshLaunchAtLogin()
            DispatchQueue.main.async {
                NSApp.keyWindow?.title = "Настройки Curty"
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
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            Text(stateLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(stateStyle.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateStyle.color.opacity(0.12), in: Capsule())
                .contentTransition(.numericText())

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(CurtyTheme.accent)
                .disabled(!isEnabled)
        }
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .animation(.easeInOut(duration: 0.16), value: stateLabel)
    }
}
