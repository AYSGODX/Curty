import SwiftUI

// ДОГОВОР О НАПРАВЛЕНИИ — «Ночной прибор»
//
// ЗАМЫСЕЛ: Curty — не окно, а передняя панель прибора, подвешенная под вырезом
// экрана. Отказ: тёмная стеклянная панель с системными значками и системным
// акцентом, то есть то, чем Curty была и чем является каждая вторая утилита
// строки меню; отказ и от ряженья под старину — прибор не костюм, а вещь.
// СВОЙ МИР: графитовый анодированный алюминий с продольной шлифовкой; плиты
// вдавлены в панель, клавиши приподняты над ней. Свет ровно один — янтарный:
// горящая лампа, залитая клавиша главного действия, тонкая линия по кромке
// поля в фокусе. Зелёная лампа — «в порядке», красная — разрушающее действие.
// Подписи гравированы: прописные, разрежённые, тёплого белого тона; серого из
// ниоткуда нет, приглушённый текст того же тёплого тона. Единственная краска
// помимо янтаря — оранжевая плитка знака «C», её трогать нельзя.
// РАССКАЗ: человек подводит курсор к вырезу, читает состояние по свету — что
// горит, то и работает — и уходит обратно в свою работу, ничего не переключив.
// ПЕРВЫЙ ЭКРАН: слева тёмный рельс-колонка с лампой у каждого инструмента,
// горит одна; сверху плитка знака. Справа гравированный заголовок под риской,
// под ним утопленная плита во всю высоту с обложкой в 132 пункта, клавишами
// плеера и шкалой с делениями; в подвале — лампа состояния и выключатель.
// ФОРМА: выбран человеком из семи нарисованных макетов, четвёртый в череде.
// ЗАВЕРШЕНИЕ: unreviewed and undocumented is unfinished; this build ends with
// the finish review, the verdict, DESIGN.md, and every shipping raster carrying
// its provenance.

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
        // Мигающая полоска в полях ввода и подсветка выделения красятся
        // системным акцентом — у большинства он синий и к панели отношения не
        // имеет. Задаётся один раз на всю панель, включая будущие поля.
        .tint(CurtyTheme.accent)
        // Панель тёмная всегда: это материал, а не тема оформления. Светлая
        // плита рядом с чужими тёмными окнами читалась бы как заплата.
        .background(
            LinearGradient(
                colors: [CurtyTheme.panelTop, CurtyTheme.panelBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(BrushedFinish())
        // Мягкий блик сверху слева — свет, падающий на металл.
        .overlay(
            RadialGradient(
                colors: [.white.opacity(0.07), .clear],
                center: .init(x: 0.3, y: -0.1), startRadius: 0, endRadius: 460
            )
            .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
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
            // Файл несут на полку — значит, она снова нужна, даже если её
            // выключали: спрятанная полка молча съела бы бросок.
            model.setTool(.shelf, hidden: false)
            withAnimation(.easeOut(duration: 0.16)) { model.select(.shelf) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if let confirmation = model.pendingConfirmation {
                CurtyConfirmationPlate(confirmation: confirmation) {
                    model.pendingConfirmation = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.pendingConfirmation?.id)
        .overlay {
            if model.isEditingRailSections {
                RailSectionsPlate(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.isEditingRailSections)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: CurtyTheme.panelCornerRadius, style: .continuous)
                    .strokeBorder(CurtyTheme.accent, lineWidth: 2)
                    .shadow(color: CurtyTheme.accent.opacity(0.5), radius: 10)
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

        let pitch = CurtyTheme.railPitch(forVisible: model.visibleTools.count)
        if drag.originIndex < drag.targetIndex, index > drag.originIndex, index <= drag.targetIndex {
            return -pitch
        }
        if drag.originIndex > drag.targetIndex, index >= drag.targetIndex, index < drag.originIndex {
            return pitch
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

    /// Кнопка инструмента. Отдельной лампы у неё нет: рядом со знаком точка
    /// читалась как сор, а не как прибор. Светится сам знак — выбранный горит
    /// янтарём на приподнятой клавише, остальные лежат в панели приглушёнными.
    @ViewBuilder
    private func railGlyph(_ section: AppModel.Tool, isSelected: Bool, isHovered: Bool) -> some View {
        Image(systemName: section.symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isSelected ? CurtyTheme.accent : CurtyTheme.engravedDim)
            .shadow(color: CurtyTheme.accent.opacity(isSelected ? 0.5 : 0), radius: 6)
            .frame(width: CurtyTheme.railButtonWidth, height: CurtyTheme.railButtonHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CurtyTheme.keyTop, CurtyTheme.keyBottom],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
    }

    private func toolButton(_ section: AppModel.Tool, at index: Int) -> some View {
        let isLifted = drag?.tool == section && drag?.isReordering == true
        let isSelected = model.selectedTool == section
        let offsetY = railOffset(for: section, at: index)

        return railGlyph(section, isSelected: isSelected, isHovered: hoveredTool == section)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { setHover(section, hovering) }
            }
            .scaleEffect(isLifted ? 1.06 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.55 : 0), radius: isLifted ? 8 : 0, y: isLifted ? 3 : 0)
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
                // Считаем по видимым: спрятанные разделы мест на экране не
                // занимают, а шаг зависит от того, насколько рельс растянут.
                let visible = model.visibleTools
                guard let origin = visible.firstIndex(of: section) else { return }
                let pitch = CurtyTheme.railPitch(forVisible: visible.count)
                let steps = Int((value.translation.height / pitch).rounded())
                let target = min(max(0, origin + steps), visible.count - 1)
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
                    model.moveTool(finished.tool, toVisibleIndex: finished.targetIndex)
                }
            }
    }

    private var toolRail: some View {
        VStack(spacing: CurtyTheme.railSpacing(forVisible: model.visibleTools.count)) {
            // Плитка — то же лицо, что у иконки приложения: графит с
            // выгравированным янтарным знаком. Рисовать её здесь заново нечем,
            // да и незачем: в бандле лежит готовая уменьшенная копия, и знак в
            // рельсе совпадает со знаком в доке до последней тени.
            Group {
                if let logo = CurtyTheme.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CurtyTheme.keyTop)
                        .overlay(
                            Image(systemName: "c.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CurtyTheme.accent)
                        )
                }
            }
            .frame(width: 36, height: 36)
            .shadow(color: CurtyTheme.accent.opacity(0.28), radius: 8)
            .help("Curty")

            // Знак — шильдик прибора, а не восьмой инструмент. Он отделён от
            // колонки риской и воздухом: стоя вплотную, он читался как ещё
            // одна кнопка в ряду.
            Rectangle()
                .fill(CurtyTheme.scribe)
                .frame(width: CurtyTheme.railButtonWidth, height: 1)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ForEach(Array(model.visibleTools.enumerated()), id: \.element) { index, section in
                toolButton(section, at: index)
            }

            Spacer(minLength: 4)

            // Риска отделяет служебный автомат от рабочих — так же, как на
            // настоящей колонке.
            Rectangle()
                .fill(CurtyTheme.scribe)
                .frame(width: CurtyTheme.railButtonWidth, height: 1)
                .padding(.bottom, 4)

            // Settings live inside the panel: a separate window would drag the
            // user to whichever Space it happens to sit on.
            Button {
                withAnimation(.easeOut(duration: 0.16)) { model.select(.settings) }
            } label: {
                railGlyph(
                    .settings,
                    isSelected: model.selectedTool == .settings,
                    isHovered: hoveredTool == .settings
                )
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { setHover(.settings, hovering) }
                }
            }
            .buttonStyle(.plain)
            .help("Настройки")
            .accessibilityLabel("Настройки")
        }
        // Колонке отступ под вырез не нужен: вырез накрывает середину экрана, а
        // рельс от него левее — проверено замером. Отступ остаётся только у
        // заголовка, у которого длинные названия хвостом уходят в вырез.
        .padding(.vertical, 12)
        .frame(width: CurtyTheme.railWidth)
        .background(
            LinearGradient(
                colors: [CurtyTheme.railTop, CurtyTheme.railBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(BrushedFinish().opacity(0.7))
        .overlay(alignment: .trailing) {
            // Кромка между колонкой и панелью: тень и следом блик.
            HStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.5)).frame(width: 1)
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
            }
        }
    }

    /// Спрашивается один раз, при первом раскрытии шторки. Всплывающее окно
    /// при входе в систему было бы ровно тем, чего от фонового приложения не
    /// ждут, а карточка в панели попадается на глаза тогда, когда человек сам
    /// пришёл к Curty.
    private var launchAtLoginPrompt: some View {
        CurtySection(title: "Запуск") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Запускать Curty при входе в систему?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CurtyTheme.engraved)
                Text("После перезагрузки она не вернётся сама, а найти её через поиск macOS не даст: приложения без окна она не показывает.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Запускать") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.preferences.setLaunchAtLogin(enabled: true)
                        }
                    }
                    .buttonStyle(CurtyProminentButtonStyle())

                    Button("Не нужно") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.preferences.launchAtLoginAsked = true
                        }
                    }
                    .buttonStyle(CurtySecondaryButtonStyle())

                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Заголовок гравирован прямо по панели и подсвечен: это шильдик прибора,
    /// а не строка приложения. Прежняя подпись «Curty» под названием раздела
    /// убрана — знак стоит в колонке, повторять его словом незачем.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.selectedTool.title.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(3)
                .foregroundStyle(CurtyTheme.engraved)
                .litEngraving()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14 + model.notchInset)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            // Риска: тонкая тень и следом блик — так выглядит прорезанная
            // в металле линия.
            VStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch model.selectedTool {
            case .media: MediaView(store: model.media, preferences: model.preferences)
            case .shelf: ShelfView(store: model.shelf, model: model)
            case .clipboard: ClipboardView(store: model.clipboard, preferences: model.preferences, model: model)
            case .snippets: SnippetsView(store: model.snippets, model: model)
            case .calendar: CalendarView(store: model.calendar, preferences: model.preferences) { model.requestPanelClose() }
            case .translate: TranslateView(store: model.translate) { model.requestPanelClose() }
            case .notes: NotesView(store: model.notes)
            case .settings: SettingsPane(model: model)
            }
        }
        .foregroundStyle(CurtyTheme.engraved)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 11)
    }
}
