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

    private var isPlaying: Bool { store.snapshot?.isPlaying == true }

    var body: some View {
        VStack(spacing: 10) {
            CurtySection(title: sourceTitle, fillsHeight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        cover

                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.snapshot?.title.isEmpty == false ? store.snapshot!.title : "Ничего не играет")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CurtyTheme.engraved)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(store.lastError == nil ? CurtyTheme.engravedDim : CurtyTheme.danger)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 6)

                            HStack(spacing: 7) {
                                transport(.previous, symbol: "backward.fill", title: "Предыдущий трек")
                                transport(
                                    .togglePlayPause,
                                    symbol: isPlaying ? "pause.fill" : "play.fill",
                                    title: isPlaying ? "Пауза" : "Воспроизвести"
                                )
                                transport(.next, symbol: "forward.fill", title: "Следующий трек")
                            }

                            if store.needsAutomationPermission {
                                Button("Разрешить управление") { store.requestAutomationAccess() }
                                    .buttonStyle(CurtyProminentButtonStyle())
                                    .padding(.top, 4)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 132)

                    Spacer(minLength: 0)

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

            statusStrip
        }
    }

    /// Обложка вставлена в панель как окошко: тень падает внутрь, по кромке
    /// тонкий блик. Пока плеер молчит, окошко не пустует — в нём приглушённый
    /// знак, как погашенная лампа.
    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CurtyTheme.groove)

            if let image = artwork.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(CurtyTheme.engravedDim)
            }
        }
        .frame(width: 132, height: 132)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.6), .white.opacity(0.12)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.2), value: artwork.image)
    }

    /// Опрос идёт раз в секунду, поэтому между ответами позиция досчитывается
    /// по часам — без этого ползунок движется рывками.
    private func interpolated(_ snapshot: MediaSnapshot, at date: Date) -> Double {
        guard snapshot.isPlaying else { return snapshot.position }
        let elapsed = max(0, date.timeIntervalSince(store.snapshotAt))
        return min(snapshot.position + elapsed, snapshot.duration)
    }

    private var sourceTitle: String {
        guard let source = store.snapshot?.source, !source.isEmpty else { return "Плеер" }
        return source
    }

    private var subtitle: String {
        if let error = store.lastError { return error }
        guard let snapshot = store.snapshot else {
            return store.isEnabled ? "Ищем текущий трек в Spotify или Music…" : "Медиасервис выключен"
        }
        return [snapshot.artist, snapshot.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// Клавиша плеера крупнее строчной и приподнята над панелью: по ней целятся
    /// не глядя, между делом. Пуск залит светом — в приборе светится то, что
    /// сейчас работает.
    @ViewBuilder
    private func transport(_ command: MediaCommand, symbol: String, title: String) -> some View {
        let isEnabled = store.isEnabled && store.snapshot != nil
        let isMain = command == .togglePlayPause

        Button {
            store.perform(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: isMain ? 15 : 12, weight: .medium))
                .foregroundStyle(isMain ? Color(red: 0.13, green: 0.10, blue: 0.03) : CurtyTheme.engraved)
                .frame(width: isMain ? 44 : 38, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaKeyStyle(isMain: isMain))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Состояние и выключатель одной строкой: лампа, надпись, клавиша. Прежде
    /// здесь стояли три одинаковые карточки, из которых две ничего не делали,
    /// а третья была кнопкой — на глаз неотличимой от них.
    private var statusStrip: some View {
        HStack(spacing: 9) {
            Lamp(isLit: store.isEnabled, colour: store.isEnabled ? CurtyTheme.success : CurtyTheme.engravedDim)
            Legend(
                text: store.isEnabled ? "подключено" : "выключено",
                tint: store.isEnabled ? CurtyTheme.engraved : CurtyTheme.engravedDim
            )

            Spacer(minLength: 8)

            Button(store.isEnabled ? "Выключить" : "Включить") {
                preferences.mediaIntegrationEnabled.toggle()
            }
            .buttonStyle(CurtySecondaryButtonStyle())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .recessedPlate(cornerRadius: 8)
    }
}

/// Клавиша прибора: приподнятый металл, при нажатии уходит внутрь. Главная
/// залита янтарём. Наведение клавиша обязана показывать сама — стиль кнопки
/// состояния не хранит, поэтому внутри живёт свой вид.
private struct MediaKeyStyle: ButtonStyle {
    let isMain: Bool

    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration, isMain: isMain)
    }

    private struct Rendered: View {
        let configuration: Configuration
        let isMain: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var isLit: Bool { isHovering && isEnabled }

        var body: some View {
            let pressed = configuration.isPressed

            Group {
                if isMain {
                    configuration.label
                        .background(
                            LinearGradient(
                                colors: [CurtyTheme.accent, CurtyTheme.accentDeep],
                                startPoint: .top, endPoint: .bottom
                            ),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.white.opacity(isLit ? 0.55 : 0.34), lineWidth: 1)
                        )
                        // Под курсором ореол разгорается: единственный способ
                        // подсветить то, что и так залито светом.
                        .shadow(color: CurtyTheme.accent.opacity(pressed ? 0 : (isLit ? 0.6 : 0.35)),
                                radius: isLit ? 10 : 7)
                } else {
                    configuration.label
                        .raisedSurface(cornerRadius: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.white.opacity(isLit ? 0.24 : 0), lineWidth: 1)
                        )
                        .brightness(isLit && !pressed ? 0.06 : 0)
                }
            }
            .offset(y: pressed ? 1 : 0)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
    }
}

/// Шкала прибора: прорезь в панели, залитая светом до отметки, с делениями
/// сверху и металлическим движком. Нажимается вся высота: в прорезь в восемь
/// пунктов попасть мышью трудно, и промах читается как «не сработало».
private struct TrackBar: View {
    let fraction: Double
    var showsTicks = false
    /// Зовётся и в процессе перетаскивания, и по отпусканию: первое двигает
    /// картинку, второе отправляет команду плееру.
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    private static let barHeight: CGFloat = 8
    private static let knobWidth: CGFloat = 9
    private static let knobHeight: CGFloat = 18
    private static let hitHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 3) {
            if showsTicks {
                GeometryReader { proxy in
                    Path { path in
                        let count = 21
                        for index in 0..<count {
                            let x = proxy.size.width * CGFloat(index) / CGFloat(count - 1)
                            let height: CGFloat = index % 5 == 0 ? 7 : 4
                            path.move(to: CGPoint(x: x, y: proxy.size.height))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height - height))
                        }
                    }
                    .stroke(CurtyTheme.engravedDim.opacity(0.55), lineWidth: 1)
                }
                .frame(height: 7)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let filled = width * min(max(fraction, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CurtyTheme.groove)
                        .frame(height: Self.barHeight)
                        .overlay(
                            Capsule().strokeBorder(.black.opacity(0.55), lineWidth: 1)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [CurtyTheme.accent, CurtyTheme.accentDeep],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: max(filled - 2, 0), height: Self.barHeight - 2)
                        .padding(.leading, 1)
                        .shadow(color: CurtyTheme.accent.opacity(0.4), radius: 4)

                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.83, blue: 0.78),
                                    Color(red: 0.55, green: 0.54, blue: 0.52),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: Self.knobWidth, height: Self.knobHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .strokeBorder(.black.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: min(max(filled - Self.knobWidth / 2, 0), max(width - Self.knobWidth, 0)))
                }
                .frame(width: width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { onScrub(Self.fraction(at: $0.location.x, width: width)) }
                        .onEnded { onCommit(Self.fraction(at: $0.location.x, width: width)) }
                )
            }
            .frame(height: Self.hitHeight)
        }
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
        HStack(spacing: 9) {
            CurtyRowButton(
                systemName: symbol,
                title: current < 1 ? "Вернуть звук" : "Заглушить",
                size: 22,
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
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(CurtyTheme.engravedDim)
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
        VStack(spacing: 2) {
            TrackBar(
                fraction: fraction,
                showsTicks: true,
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
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(CurtyTheme.engravedDim)
        }
        .accessibilityLabel("Позиция в треке")
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
