import SwiftUI

enum CurtyTheme {
    static let panelCornerRadius: CGFloat = 24
    static let railWidth: CGFloat = 58
    static let railButtonWidth: CGFloat = 48
    static let railButtonHeight: CGFloat = 36
    static let railButtonSpacing: CGFloat = 6
    static let railButtonCornerRadius: CGFloat = 11

    /// Row actions sit in a fixed-width cluster so the file name always ends at
    /// the same place instead of being eaten by however many buttons a row has.
    static let rowActionSize: CGFloat = 28
    static let rowActionSpacing: CGFloat = 3
    /// Gap that isolates the destructive action, so a miss aimed at the button
    /// beside it does not land on "remove".
    static let rowActionDestructiveGap: CGFloat = 10
    static let rowActionClusterWidth: CGFloat = 97

    /// One slot from the centre of one rail button to the next, used to turn a
    /// drag distance into how many places the icon has travelled.
    static var railButtonPitch: CGFloat { railButtonHeight + railButtonSpacing }

    /// Below this the pointer never left the icon, so the press is a click.
    static let railDragThreshold: CGFloat = 4

    static let accent = Color(red: 0.95, green: 0.49, blue: 0.28)
    static let warmBackground = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let warmSurface = Color(red: 1.00, green: 0.99, blue: 0.97)
    static let darkBackground = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let darkSurface = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let darkRail = Color(red: 0.095, green: 0.095, blue: 0.11)
    static let success = Color(red: 0.25, green: 0.68, blue: 0.48)
}

/// Системные кнопки и переключатели macOS рисуются графитом, пока окно не
/// станет ключевым, а панель специально не забирает фокус при наведении.
/// Сказать им обратное через controlActiveState не выходит — они читают
/// состояние окна напрямую. Поэтому акцентные контролы Curty рисует сама:
/// обычная заливка Color от активности окна не зависит.
struct CurtyProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration)
    }

    private struct Rendered: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(CurtyTheme.accent.opacity(fill))
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }

        private var fill: Double {
            if configuration.isPressed { return 0.72 }
            return isHovering && isEnabled ? 1 : 0.9
        }
    }
}

struct CurtySecondaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration, isDestructive: isDestructive)
    }

    private struct Rendered: View {
        let configuration: Configuration
        let isDestructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.caption.weight(.medium))
                .foregroundStyle(isDestructive ? Color.red : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(fill))
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }

        private var fill: Double {
            if configuration.isPressed { return 0.18 }
            return isHovering && isEnabled ? 0.13 : 0.075
        }
    }
}

/// Переключатель по той же причине нарисован вручную: системный NSSwitch
/// теряет акцент вместе с окном.
struct CurtySwitch: View {
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        // Именно Button, а не жест: так переключатель доступен с клавиатуры и
        // VoiceOver, чего у самодельного тумблера на onTapGesture не было.
        Button {
            withAnimation(.easeOut(duration: 0.16)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? CurtyTheme.accent : Color.primary.opacity(0.22))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

/// Ошибку записи некуда деть, кроме экрана: без неё пользователь узнаёт о
/// потерянной заметке через часы, когда восстанавливать уже нечего.
struct CurtyErrorRow: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let onDismiss {
                CurtyRowButton(systemName: "xmark", title: "Скрыть сообщение", size: 20, glyphSize: 10, action: onDismiss)
            }
        }
        .font(.caption)
        .foregroundStyle(.red)
    }
}

/// Окно отмены удаления. Живёт несколько секунд и исчезает само.
struct CurtyUndoBar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(CurtyTheme.accent)
            Text(message)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Отменить", action: onUndo)
                .buttonStyle(CurtySecondaryButtonStyle())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity)
    }
}

/// Icon-only action. Bare glyphs give no sign they are clickable, so this lights
/// up under the pointer and carries a tooltip explaining itself.
struct CurtyRowButton: View {
    let systemName: String
    let title: String
    var isDestructive = false
    var size: CGFloat = 24
    var glyphSize: CGFloat = 12
    var isEnabled = true
    /// Set for actions whose result is invisible — copying above all — so the
    /// button briefly turns into a tick and says the deed is done.
    var confirmsWith: String?
    /// То же действие бывает доступно с клавиатуры, а галочка должна выглядеть
    /// одинаково в обоих случаях. Новое значение — новое подтверждение.
    var confirmationToken: UUID?
    let action: () -> Void

    @State private var isHovering = false
    @State private var isConfirming = false
    @State private var confirmation: Task<Void, Never>?

    private var isLit: Bool { isHovering && isEnabled }

    var body: some View {
        Button {
            action()
            confirmIfNeeded()
        } label: {
            Image(systemName: isConfirming ? (confirmsWith ?? systemName) : systemName)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                        .fill(isConfirming ? CurtyTheme.success.opacity(0.18) : (isLit ? tint.opacity(0.16) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(title)
        .accessibilityLabel(title)
        .onChange(of: confirmationToken) { _, token in
            guard token != nil else { return }
            confirmIfNeeded()
        }
    }

    private func confirmIfNeeded() {
        guard confirmsWith != nil else { return }
        confirmation?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { isConfirming = true }
        confirmation = Task {
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isConfirming = false }
        }
    }

    private var tint: Color {
        if isConfirming { return CurtyTheme.success }
        guard isEnabled else { return .secondary }
        if isDestructive { return isHovering ? .red : .secondary }
        return isHovering ? CurtyTheme.accent : .secondary
    }
}

/// Hover feedback for controls that draw themselves — system buttons, switches —
/// where a background of our own cannot be slipped underneath.
private struct CurtyHoverLift: ViewModifier {
    var scale: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.09 : 0)
            .scaleEffect(isHovering ? scale : 1)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
    }
}

extension View {
    func curtyHoverLift(scale: CGFloat = 1.04) -> some View {
        modifier(CurtyHoverLift(scale: scale))
    }
}

struct CurtyCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? CurtyTheme.darkSurface : CurtyTheme.warmSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
            )
    }
}
