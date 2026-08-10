import SwiftUI

private struct RailDrag: Equatable {
    let tool: AppModel.Tool
    let originIndex: Int
    let targetIndex: Int
    /// Kept continuous so the dragged icon can sit between slots instead of
    /// jumping from one to the next.
    let translation: CGFloat
    /// False until the pointer has travelled far enough to mean "move", which
    /// is what keeps a plain click from being read as a one-slot drag.
    let isReordering: Bool
}

struct PanelRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    @State private var drag: RailDrag?
    @State private var isDropTarget = false
    @State private var hoveredTool: AppModel.Tool?

    var body: some View {
        HStack(spacing: 0) {
            toolRail
            VStack(spacing: 0) {
                header
                if model.preferences.shouldAskAboutLaunchAtLogin {
                    launchAtLoginPrompt
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 488, height: 420)
        .background(colorScheme == .dark ? CurtyTheme.darkBackground : CurtyTheme.warmBackground)
        .clipShape(RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
        )
        // Escape доходит только когда панель уже стала ключевой, то есть после
        // клика по ней. Остальные случаи закрывает щелчок мимо панели.
        .onExitCommand { model.requestPanelClose() }
        // Files land anywhere on the panel, not only on the Shelf screen: the
        // panel unfolds on whichever tool was last used, and hunting for the
        // right tab mid-drag is not something a shelf should ask for.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.shelf.addUserSelectedFiles(files)
            withAnimation(.easeOut(duration: 0.16)) { model.select(.shelf) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous)
                    .strokeBorder(CurtyTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(
                        CurtyTheme.accent.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    /// The dragged icon follows the pointer exactly; the others step aside by a
    /// whole slot. Reordering the array instead would snap the icon from slot to
    /// slot, which is what made the drag feel jerky.
    private func railOffset(for section: AppModel.Tool, at index: Int) -> CGFloat {
        guard let drag, drag.isReordering else { return 0 }
        if section == drag.tool { return drag.translation }

        if drag.originIndex < drag.targetIndex, index > drag.originIndex, index <= drag.targetIndex {
            return -CurtyTheme.railButtonPitch
        }
        if drag.originIndex > drag.targetIndex, index >= drag.targetIndex, index < drag.originIndex {
            return CurtyTheme.railButtonPitch
        }
        return 0
    }

    private func setHover(_ section: AppModel.Tool, _ hovering: Bool) {
        if hovering {
            hoveredTool = section
        } else if hoveredTool == section {
            hoveredTool = nil
        }
    }

    private func railTint(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return .white }
        return isHovered ? .primary : .secondary
    }

    private func railBackground(isSelected: Bool, isLifted: Bool, isHovered: Bool) -> Color {
        if isSelected { return CurtyTheme.accent }
        if isLifted { return .primary.opacity(0.14) }
        return isHovered ? .primary.opacity(0.09) : .clear
    }

    private func toolButton(_ section: AppModel.Tool, at index: Int) -> some View {
        let isLifted = drag?.tool == section && drag?.isReordering == true
        let isSelected = model.selectedTool == section
        let offsetY = railOffset(for: section, at: index)

        return Image(systemName: section.symbol)
            .font(.system(size: 15, weight: .medium))
            .frame(width: CurtyTheme.railButtonWidth, height: CurtyTheme.railButtonHeight)
            .foregroundStyle(railTint(isSelected: isSelected, isHovered: hoveredTool == section))
            .background(
                RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                    .fill(railBackground(
                        isSelected: isSelected,
                        isLifted: isLifted,
                        isHovered: hoveredTool == section
                    ))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { setHover(section, hovering) }
            }
            // A frame alone is not hit-testable where it is transparent, so
            // without this only the glyph itself would answer the pointer.
            .contentShape(Rectangle())
            .scaleEffect(isLifted ? 1.08 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: isLifted ? 7 : 0, y: isLifted ? 3 : 0)
            .offset(y: offsetY)
            // The icon under the pointer must not lag behind it, so only the
            // ones stepping aside are animated.
            .animation(isLifted ? nil : .easeOut(duration: 0.16), value: offsetY)
            .zIndex(isLifted ? 1 : 0)
            .gesture(reorderGesture(for: section))
            .help(section.title)
            .accessibilityLabel(section.title)
            .accessibilityAddTraits(.isButton)
            // Управление указателем — жест, поэтому активировать иконку иначе
            // было нечем: VoiceOver объявлял кнопку, которая не срабатывает.
            .accessibilityAction { model.select(section) }
    }

    /// Reordering is done by hand rather than with the system drag-and-drop:
    /// a drag session brands the pointer with a copy badge, paints its own
    /// target highlight, and only reports a position while it is over one of
    /// the buttons — never in the gaps between them.
    private func reorderGesture(for section: AppModel.Tool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let origin = model.orderedTools.firstIndex(of: section) else { return }
                let steps = Int((value.translation.height / CurtyTheme.railButtonPitch).rounded())
                let target = min(max(0, origin + steps), model.orderedTools.count - 1)
                // Deliberately unanimated: this is the pointer's own position.
                drag = RailDrag(
                    tool: section,
                    originIndex: origin,
                    targetIndex: target,
                    translation: value.translation.height,
                    isReordering: abs(value.translation.height) > CurtyTheme.railDragThreshold
                )
            }
            .onEnded { _ in
                let finished = drag
                withAnimation(.easeOut(duration: 0.16)) {
                    drag = nil
                    // A press that never travelled is simply a click.
                    guard let finished, finished.isReordering else {
                        model.select(section)
                        return
                    }
                    model.moveTool(finished.tool, toIndex: finished.targetIndex)
                }
            }
    }

    private var toolRail: some View {
        VStack(spacing: CurtyTheme.railButtonSpacing) {
            // Плитку рисует приложение, а в бандле лежит только знак без фона:
            // так его размер можно подогнать под соседние значки. Запасной
            // вариант на случай пропавшего файла — прежний символ.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CurtyTheme.accent)
                if let logo = CurtyTheme.logo {
                    // Не во всю плитку: «C» — сплошная фигура, и в полный рост
                    // она выглядит ярче тонких значков инструментов под ней. Но
                    // и уменьшать сильно нельзя — вырез перестаёт читаться как
                    // вырез и превращается в точку. Двадцать восемь — середина.
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
            .help("Curty")

            Spacer().frame(height: 3)

            ForEach(Array(model.orderedTools.enumerated()), id: \.element) { index, section in
                toolButton(section, at: index)
            }

            Spacer(minLength: 4)

            // Settings live inside the panel: a separate window would drag the
            // user to whichever Space it happens to sit on.
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    model.select(.settings)
                }
            } label: {
                Image(systemName: AppModel.Tool.settings.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: CurtyTheme.railButtonWidth, height: CurtyTheme.railButtonHeight)
                    .foregroundStyle(railTint(
                        isSelected: model.selectedTool == .settings,
                        isHovered: hoveredTool == .settings
                    ))
                    .background(
                        RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                            .fill(railBackground(
                                isSelected: model.selectedTool == .settings,
                                isLifted: false,
                                isHovered: hoveredTool == .settings
                            ))
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { setHover(.settings, hovering) }
                    }
            }
            .buttonStyle(.plain)
            .help("Настройки")
            .accessibilityLabel("Настройки")
        }
        .padding(.vertical, 12)
        .frame(width: CurtyTheme.railWidth)
        .background(colorScheme == .dark ? CurtyTheme.darkRail : Color.black.opacity(0.035))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
        }
    }

    /// Спрашивается один раз, при первом раскрытии шторки. Всплывающее окно
    /// при входе в систему было бы ровно тем, чего от фонового приложения не
    /// ждут, а карточка в панели попадается на глаза тогда, когда человек сам
    /// пришёл к Curty.
    private var launchAtLoginPrompt: some View {
        CurtyCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Запускать Curty при входе в систему?")
                    .font(.system(size: 12, weight: .semibold))
                Text("После перезагрузки она не вернётся сама, а найти её через поиск macOS не даст: приложения без окна она не показывает.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Запускать") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.preferences.setLaunchAtLogin(enabled: true)
                        }
                    }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .curtyHoverLift()

                    Button("Не нужно") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.preferences.launchAtLoginAsked = true
                        }
                    }
                    .buttonStyle(CurtySecondaryButtonStyle())
                    .curtyHoverLift()

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedTool.title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Curty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch model.selectedTool {
            case .media: MediaView(store: model.media, preferences: model.preferences)
            case .shelf: ShelfView(store: model.shelf, model: model)
            case .clipboard: ClipboardView(store: model.clipboard, preferences: model.preferences)
            case .snippets: SnippetsView(store: model.snippets, model: model)
            case .calendar: CalendarView(store: model.calendar, preferences: model.preferences) { model.requestPanelClose() }
            case .translate: TranslateView(store: model.translate) { model.requestPanelClose() }
            case .notes: NotesView(store: model.notes)
            case .settings: SettingsPane(model: model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
