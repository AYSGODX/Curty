import SwiftUI

/// Settings render inside the panel rather than in a window of their own: a
/// window belongs to a Space, and activating the app to show it threw the user
/// onto whichever desktop that window happened to live on.
struct SettingsPane: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var preferences: Preferences
    @ObservedObject private var updates: UpdateChecker

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

                section("Левая панель") {
                    SettingsToggleRow(
                        title: "Не мешать в полноэкранном режиме",
                        detail: "Пока игра, видео или презентация занимают весь экран, шторка не раскрывается.",
                        isOn: $preferences.respectFullScreenEnabled,
                        isEnabled: true,
                        stateLabel: preferences.respectFullScreenEnabled ? "Включено" : "Выключено",
                        stateStyle: preferences.respectFullScreenEnabled ? .active : .inactive
                    )
                    Divider()
                    Text("Иконки в левом столбце можно перетаскивать, чтобы поставить нужный инструмент первым. Ненужные разделы можно выключить.")
                        .font(.caption2)
                        .foregroundStyle(CurtyTheme.engravedDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Изменить разделы") { model.isEditingRailSections = true }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .foregroundStyle(preferences.launchAtLoginState == .requiresApproval ? CurtyTheme.accent : CurtyTheme.engravedDim)
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

                section("Локальные данные") {
                    Text("Удаляет историю буфера, ссылки с полки, сниппеты и заметки с этого Mac.")
                        .font(.caption2)
                        .foregroundStyle(CurtyTheme.engravedDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Удалить все локальные данные") {
                        model.confirm(
                            "Удалить все локальные данные?",
                            detail: "История буфера, ссылки с полки, сниппеты и заметки будут стёрты. Это нельзя отменить.",
                            actionTitle: "Удалить"
                        ) { model.deleteAllLocalData() }
                    }
                    .buttonStyle(CurtySecondaryButtonStyle(isDestructive: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 4)
        }

    }

    private var timeZoneRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Показывать время в поясе")
                    .font(.system(size: 12, weight: .medium))
                Text("Пригодится, если часы на маке не совпадают с местом, где вы находитесь. По умолчанию Curty берёт пояс системы.")
                    .font(.caption2)
                    .foregroundStyle(CurtyTheme.engravedDim)
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
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Legend(text: updateStatus.label, size: 8, tint: updateStatus.style.color)
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
            .foregroundStyle(CurtyTheme.engravedDim)
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
        CurtySection(title: title) {
            VStack(spacing: 8) { content() }
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
        case .active: CurtyTheme.engraved
        case .warning: CurtyTheme.accent
        case .inactive, .unavailable: CurtyTheme.engravedDim
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
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Legend(text: stateLabel, size: 8, tint: stateStyle.color)
                .contentTransition(.numericText())

            CurtySwitch(isOn: $isOn, isEnabled: isEnabled)
        }
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .animation(.easeInOut(duration: 0.16), value: stateLabel)
    }
}

/// Съёмная плита «Разделы левой панели»: включение и выключение разделов и
/// сброс всей левой панели. Живёт поверх погашенной панели, как плита
/// подтверждения, — системному окну на приборе не место.
struct RailSectionsPlate: View {
    @ObservedObject var model: AppModel
    @State private var drag: PlateDrag?

    /// Строка фиксированной высоты: шаг перетаскивания должен быть числом,
    /// а не догадкой по содержимому.
    private static let rowHeight: CGFloat = 28
    private static let rowSpacing: CGFloat = 6
    private static var rowPitch: CGFloat { rowHeight + rowSpacing }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { model.isEditingRailSections = false }

            VStack(alignment: .leading, spacing: 10) {
                Text("Разделы левой панели")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CurtyTheme.engraved)

                Text("Выключенный раздел прячется из колонки, его данные никуда не деваются. Строки можно перетаскивать — колонка повторит порядок. Настройки выключить нельзя — это дверь обратно.")
                    .font(.system(size: 11))
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(model.orderedTools.enumerated()), id: \.element) { index, tool in
                        row(for: tool, at: index)
                    }
                }

                Rectangle().fill(CurtyTheme.scribe).frame(height: 1)

                HStack(spacing: 9) {
                    Button("Сбросить левую панель") { model.resetRailSettings() }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .help("Вернуть исходный порядок и включить все разделы")
                    Spacer(minLength: 0)
                    Button("Готово") { model.isEditingRailSections = false }
                        .buttonStyle(CurtyProminentButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(width: 312)
            .background(
                LinearGradient(
                    colors: [CurtyTheme.keyTop, CurtyTheme.keyBottom],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .black.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
        }
    }

    @ViewBuilder
    private func row(for tool: AppModel.Tool, at index: Int) -> some View {
        let isLifted = drag?.tool == tool && drag?.isReordering == true

        HStack(spacing: 8) {
            // Перетаскивание живёт на левой части строки; тумблер справа —
            // отдельная кнопка, и жест его не касается.
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CurtyTheme.engravedDim.opacity(0.6))
                Image(systemName: tool.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(
                        model.hiddenTools.contains(tool)
                            ? CurtyTheme.engravedDim
                            : CurtyTheme.engraved
                    )
                Text(tool.title)
                    .font(.system(size: 12))
                    .foregroundStyle(CurtyTheme.engraved)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            // Перетаскивание ведёт роутер нажатий, а не жест SwiftUI: жесты в
            // этой панели отдают события с пропусками, и строка догоняла
            // курсор рывками вместо того, чтобы ехать под ним.
            .onLeftMouseDown(
                onDragChanged: { translation in dragChanged(tool, by: translation) },
                onDragEnded: { dragEnded() },
                perform: { _ in }
            )

            CurtySwitch(isOn: Binding(
                get: { !model.hiddenTools.contains(tool) },
                set: { model.setTool(tool, hidden: !$0) }
            ))
            .accessibilityLabel("Раздел «\(tool.title)»")
        }
        .frame(height: Self.rowHeight)
        .scaleEffect(isLifted ? 1.03 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.5 : 0), radius: isLifted ? 7 : 0, y: isLifted ? 3 : 0)
        // Анимациями управляют сами обновления: перевод тащимой строки
        // приходит без анимации, расступание соседей — с ней.
        .offset(y: offset(for: tool, at: index))
        .zIndex(isLifted ? 1 : 0)
    }

    /// Перенос ручной — как у рельса, и по той же причине: системная сессия
    /// перетаскивания клеймит курсор значком копирования и молчит в зазорах
    /// между строками.
    private func dragChanged(_ tool: AppModel.Tool, by translation: CGFloat) {
        guard let origin = model.orderedTools.firstIndex(of: tool) else { return }
        let steps = Int((translation / Self.rowPitch).rounded())
        let target = min(max(0, origin + steps), model.orderedTools.count - 1)
        let updated = PlateDrag(
            tool: tool,
            originIndex: origin,
            targetIndex: target,
            translation: translation,
            isReordering: abs(translation) > CurtyTheme.railDragThreshold
        )
        if drag?.targetIndex != target || drag?.isReordering != updated.isReordering {
            // Сменился слот — соседи расступаются плавно.
            withAnimation(.easeOut(duration: 0.16)) { drag = updated }
        } else {
            // Только перевод: строка едет ровно под курсором, без анимации.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drag = updated }
        }
    }

    private func dragEnded() {
        let finished = drag
        withAnimation(.easeOut(duration: 0.16)) {
            drag = nil
            guard let finished, finished.isReordering else { return }
            // Полный список: плита показывает и спрятанные разделы.
            model.moveTool(finished.tool, toIndex: finished.targetIndex)
        }
    }

    private func offset(for tool: AppModel.Tool, at index: Int) -> CGFloat {
        guard let drag, drag.isReordering else { return 0 }
        if tool == drag.tool { return drag.translation }
        if drag.originIndex < drag.targetIndex, index > drag.originIndex, index <= drag.targetIndex {
            return -Self.rowPitch
        }
        if drag.originIndex > drag.targetIndex, index >= drag.targetIndex, index < drag.originIndex {
            return Self.rowPitch
        }
        return 0
    }
}

/// Перетаскиваемая строка плиты: кто едет, откуда, куда и насколько сдвинут.
private struct PlateDrag: Equatable {
    let tool: AppModel.Tool
    let originIndex: Int
    let targetIndex: Int
    let translation: CGFloat
    let isReordering: Bool
}
