import SwiftUI
import CurtyShared

struct MediaView: View {
    @ObservedObject var store: MediaStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 12) {
            CurtyCard {
                VStack(spacing: 10) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CurtyTheme.accent.opacity(0.14))
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 25, weight: .medium))
                                .foregroundStyle(CurtyTheme.accent)
                        }
                        .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.snapshot?.title.isEmpty == false ? store.snapshot!.title : "Ничего не играет")
                            .font(.system(size: 15, weight: .semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(store.lastError == nil ? Color.secondary : Color.orange)
                            .lineLimit(2)
                        HStack(spacing: 18) {
                            mediaButton(.previous, symbol: "backward.fill")
                            mediaButton(
                                .togglePlayPause,
                                symbol: store.snapshot?.isPlaying == true ? "pause.fill" : "play.fill"
                            )
                            .font(.system(size: 17))
                            mediaButton(.next, symbol: "forward.fill")
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)

                        if store.needsAutomationPermission {
                            Button("Разрешить управление") {
                                store.requestAutomationAccess()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(CurtyTheme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let snapshot = store.snapshot, snapshot.duration > 0 {
                    MediaScrubber(
                        position: snapshot.position,
                        duration: snapshot.duration,
                        onSeek: { store.seek(to: $0) }
                    )
                }
                }
            }

            HStack(spacing: 10) {
                compactAction(store.isEnabled ? "Подключено" : "Медиа выкл.", icon: store.isEnabled ? "checkmark.shield" : "hand.raised")
                compactAction(store.snapshot?.source.isEmpty == false ? store.snapshot!.source : "Нет источника", icon: "hifispeaker")
                Button {
                    preferences.mediaIntegrationEnabled.toggle()
                } label: {
                    compactAction(store.isEnabled ? "Выключить" : "Включить", icon: "power")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subtitle: String {
        if let error = store.lastError { return error }
        guard let snapshot = store.snapshot else {
            return store.isEnabled ? "Ищем текущий трек в Spotify или Music…" : "Медиасервис выключен"
        }
        return [snapshot.artist, snapshot.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private func mediaButton(_ command: MediaCommand, symbol: String) -> some View {
        Button { store.perform(command) } label: { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .disabled(!store.isEnabled || store.snapshot == nil)
    }

    private func compactAction(_ title: String, icon: String) -> some View {
        CurtyCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CurtyTheme.accent)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Position within the track, draggable to seek. While a drag is in flight the
/// local fraction wins, otherwise the once-a-second poll would yank the handle
/// back under the user's finger.
private struct MediaScrubber: View {
    let position: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(CurtyTheme.accent)
                        .frame(width: proxy.size.width * fraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = Self.fraction(at: value.location.x, width: proxy.size.width)
                        }
                        .onEnded { value in
                            let target = Self.fraction(at: value.location.x, width: proxy.size.width)
                            dragFraction = nil
                            onSeek(target * duration)
                        }
                )
            }
            .frame(height: 5)

            HStack {
                Text(Self.timeLabel(fraction * duration))
                Spacer()
                Text(Self.timeLabel(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Позиция в треке")
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
