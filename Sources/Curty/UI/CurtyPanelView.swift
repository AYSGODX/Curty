import SwiftUI

struct PanelRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel
    @State private var dropTarget: AppModel.Tool?

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

    private var toolRail: some View {
        VStack(spacing: 6) {
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

            ForEach(model.orderedTools) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        model.select(section)
                    }
                } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: CurtyTheme.railButtonWidth, height: CurtyTheme.railButtonHeight)
                        .foregroundStyle(model.selectedTool == section ? .white : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: CurtyTheme.railButtonCornerRadius, style: .continuous)
                                .fill(model.selectedTool == section ? CurtyTheme.accent : .clear)
                        )
                        // A frame alone is not hit-testable where it is transparent,
                        // so without this only the glyph itself answered the click.
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if dropTarget == section {
                                Capsule()
                                    .fill(CurtyTheme.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, 4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
                // A click carries no movement, so it still selects; the system
                // only starts a drag once the pointer passes its own threshold.
                .onDrag { NSItemProvider(object: section.rawValue as NSString) }
                .dropDestination(for: String.self) { items, _ in
                    dropTarget = nil
                    guard let raw = items.first,
                          let moved = AppModel.Tool(rawValue: raw) else { return false }
                    withAnimation(.easeOut(duration: 0.18)) {
                        model.moveTool(moved, before: section)
                    }
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        dropTarget = section
                    } else if dropTarget == section {
                        dropTarget = nil
                    }
                }
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
