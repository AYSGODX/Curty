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
