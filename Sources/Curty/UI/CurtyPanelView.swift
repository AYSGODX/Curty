import SwiftUI

private struct RailDrag: Equatable {
    let tool: AppModel.Tool
    let targetIndex: Int
    /// False until the pointer has travelled far enough to mean "move", which
    /// is what keeps a plain click from being read as a one-slot drag.
    let isReordering: Bool
}

struct PanelRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    @State private var drag: RailDrag?

    var body: some View {
        HStack(spacing: 0) {
            toolRail
            VStack(spacing: 0) {
                header
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
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 28, y: 14)
    }

    /// While an icon is being dragged the rail renders the order it would end up
    /// in. The arrangement itself is the feedback, so there is no separate
    /// insertion marker that can fail to show up between the buttons.
    private var displayedTools: [AppModel.Tool] {
        guard let drag, drag.isReordering else { return model.orderedTools }
        return ToolOrderPolicy.move(drag.tool, toIndex: drag.targetIndex, in: model.orderedTools)
    }

    private func toolButton(_ section: AppModel.Tool) -> some View {
        let isLifted = drag?.tool == section && drag?.isReordering == true
        let isSelected = model.selectedTool == section

        return Image(systemName: section.symbol)
            .font(.system(size: 15, weight: .medium))
            .frame(width: CurtyTheme.railButtonWidth, height: CurtyTheme.railButtonHeight)
            .foregroundStyle(isSelected ? .white : .secondary)
            .background(
                RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                    .fill(isSelected ? CurtyTheme.accent : (isLifted ? Color.primary.opacity(0.14) : .clear))
            )
            // A frame alone is not hit-testable where it is transparent, so
            // without this only the glyph itself would answer the pointer.
            .contentShape(Rectangle())
            .scaleEffect(isLifted ? 1.08 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: isLifted ? 7 : 0, y: isLifted ? 3 : 0)
            .zIndex(isLifted ? 1 : 0)
            .gesture(reorderGesture(for: section))
            .help(section.title)
            .accessibilityLabel(section.title)
            .accessibilityAddTraits(.isButton)
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
                let next = RailDrag(
                    tool: section,
                    targetIndex: target,
                    isReordering: abs(value.translation.height) > CurtyTheme.railDragThreshold
                )
                guard next != drag else { return }
                withAnimation(.easeOut(duration: 0.14)) { drag = next }
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
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CurtyTheme.accent.gradient)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .help("Curty")

            Spacer().frame(height: 3)

            ForEach(displayedTools) { section in
                toolButton(section)
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
                    .foregroundStyle(model.selectedTool == .settings ? .white : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                            .fill(model.selectedTool == .settings ? CurtyTheme.accent : .clear)
                    )
                    .contentShape(Rectangle())
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
            case .shelf: ShelfView(store: model.shelf)
            case .clipboard: ClipboardView(store: model.clipboard, preferences: model.preferences)
            case .snippets: SnippetsView(store: model.snippets)
            case .calendar: CalendarView(store: model.calendar)
            case .translate: TranslateView()
            case .notes: NotesView(store: model.notes)
            case .settings: SettingsPane(model: model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
