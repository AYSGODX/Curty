import SwiftUI

enum CurtyTheme {
    static let panelCornerRadius: CGFloat = 24
    static let railWidth: CGFloat = 58
    static let railButtonWidth: CGFloat = 48
    static let railButtonHeight: CGFloat = 36
    static let railButtonSpacing: CGFloat = 6
    static let railButtonCornerRadius: CGFloat = 11

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

/// Icon-only action in a list row. Bare glyphs give no sign they are clickable,
/// so this lights up under the pointer and carries a tooltip explaining itself.
struct CurtyRowButton: View {
    let systemName: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? tint.opacity(0.16) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private var tint: Color {
        if isDestructive { return isHovering ? .red : .secondary }
        return isHovering ? CurtyTheme.accent : .secondary
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
