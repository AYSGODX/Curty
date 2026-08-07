import SwiftUI

struct MediaView: View {
    @ObservedObject var store: MediaStore
    @ObservedObject var preferences: Preferences
    @ObservedObject private var artwork: ArtworkLoader

    init(store: MediaStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        _artwork = ObservedObject(wrappedValue: store.artwork)
    }

    var body: some View {
        VStack(spacing: 12) {
            CurtyCard {
                VStack(spacing: 10) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CurtyTheme.accent.opacity(0.14))
                        .overlay {
                            if let cover = artwork.image {
                                Image(nsImage: cover)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 25, weight: .medium))
                                    .foregroundStyle(CurtyTheme.accent)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(width: 68, height: 68)
                        .animation(.easeOut(duration: 0.2), value: artwork.image)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.snapshot?.title.isEmpty == false ? store.snapshot!.title : "Ничего не играет")
                            .font(.system(size: 15, weight: .semibold))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(store.lastError == nil ? Color.secondary : Color.orange)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            mediaButton(.previous, symbol: "backward.fill", title: "Предыдущий трек")
                            mediaButton(
                                .togglePlayPause,
                                symbol: store.snapshot?.isPlaying == true ? "pause.fill" : "play.fill",
                                title: store.snapshot?.isPlaying == true ? "Пауза" : "Воспроизвести",
                                glyphSize: 16
                            )
                            mediaButton(.next, symbol: "forward.fill", title: "Следующий трек")
                        }
                        .padding(.top, 3)

                        if store.needsAutomationPermission {
                            Button("Разрешить управление") {
                                store.requestAutomationAccess()
                            }
                            .buttonStyle(CurtyProminentButtonStyle())
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let snapshot = store.snapshot, snapshot.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 0.2)) { context in
                        MediaScrubber(
                            position: interpolated(snapshot, at: context.date),
                            duration: snapshot.duration,
                            onSeek: { store.seek(to: $0) }
                        )
                    }
                }

                // Громкость самого плеера. Ползунок появляется, только если
                // плеер её сообщил: выдуманный ноль хуже, чем ничего.
                if let volume = store.snapshot?.volume {
                    MediaVolumeSlider(
                        volume: volume,
                        onChange: { store.setVolume($0) },
                        onToggleMute: { store.toggleMute() }
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

    /// Опрос идёт раз в секунду, поэтому между ответами позиция досчитывается
    /// по часам — без этого ползунок движется рывками.
    private func interpolated(_ snapshot: MediaSnapshot, at date: Date) -> Double {
        guard snapshot.isPlaying else { return snapshot.position }
        let elapsed = max(0, date.timeIntervalSince(store.snapshotAt))
        return min(snapshot.position + elapsed, snapshot.duration)
    }

    private var subtitle: String {
        if let error = store.lastError { return error }
        guard let snapshot = store.snapshot else {
            return store.isEnabled ? "Ищем текущий трек в Spotify или Music…" : "Медиасервис выключен"
        }
        return [snapshot.artist, snapshot.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private func mediaButton(
        _ command: MediaCommand,
        symbol: String,
        title: String,
        glyphSize: CGFloat = 13
    ) -> some View {
        CurtyRowButton(
            systemName: symbol,
            title: title,
            size: 30,
            glyphSize: glyphSize,
            isEnabled: store.isEnabled && store.snapshot != nil
        ) {
            store.perform(command)
        }
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
/// Полоса с точкой на конце заливки. Сама полоса тонкая, а нажимается вся
/// высота: в пять пунктов попасть мышью трудно, и промах по дорожке читается
/// как «не сработало».
private struct TrackBar: View {
    let fraction: Double
    /// Зовётся и в процессе перетаскивания, и по отпусканию: первое двигает
    /// картинку, второе отправляет команду плееру.
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    private static let barHeight: CGFloat = 5
    private static let knobSize: CGFloat = 9
    private static let hitHeight: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.12))
                    .frame(height: Self.barHeight)
                Capsule()
                    .fill(CurtyTheme.accent)
                    .frame(width: filled, height: Self.barHeight)
                Circle()
                    .fill(CurtyTheme.accent)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    // Точка стоит центром на конце заливки и не вылезает за
                    // края полосы на нуле и на максимуме.
                    .offset(x: min(max(filled - Self.knobSize / 2, 0), max(width - Self.knobSize, 0)))
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(Self.fraction(at: $0.location.x, width: width)) }
                    .onEnded { onCommit(Self.fraction(at: $0.location.x, width: width)) }
            )
        }
        .frame(height: Self.hitHeight)
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}

private struct MediaVolumeSlider: View {
    let volume: Double
    let onChange: (Double) -> Void
    let onToggleMute: () -> Void

    @State private var dragValue: Double?

    private var current: Double { dragValue ?? volume }

    private var symbol: String {
        switch current {
        case ..<1: return "speaker.slash"
        case ..<34: return "speaker.wave.1"
        case ..<67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            CurtyRowButton(
                systemName: symbol,
                title: current < 1 ? "Вернуть звук" : "Заглушить",
                size: 20,
                glyphSize: 11,
                action: onToggleMute
            )

            TrackBar(
                fraction: current / 100,
                onScrub: { dragValue = $0 * 100 },
                onCommit: { fraction in
                    dragValue = nil
                    onChange(fraction * 100)
                }
            )

            Text("\(Int(current.rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityLabel("Громкость плеера")
    }
}

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
        VStack(spacing: 0) {
            TrackBar(
                fraction: fraction,
                onScrub: { dragFraction = $0 },
                onCommit: { target in
                    dragFraction = nil
                    onSeek(target * duration)
                }
            )

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

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
