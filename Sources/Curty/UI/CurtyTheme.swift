import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CurtyTheme {
    static let panelCornerRadius: CGFloat = 20
    static let railWidth: CGFloat = 58
    static let railButtonWidth: CGFloat = 46
    static let railButtonHeight: CGFloat = 34
    static let railButtonSpacing: CGFloat = 5
    static let railButtonCornerRadius: CGFloat = 8

    /// Row actions sit in a fixed-width cluster so the file name always ends at
    /// the same place instead of being eaten by however many buttons a row has.
    static let rowActionSize: CGFloat = 27
    static let rowActionSpacing: CGFloat = 4
    /// Gap that isolates the destructive action, so a miss aimed at the button
    /// beside it does not land on "remove".
    static let rowActionDestructiveGap: CGFloat = 10
    static let rowActionClusterWidth: CGFloat = 100

    /// One slot from the centre of one rail button to the next, used to turn a
    /// drag distance into how many places the icon has travelled.
    static var railButtonPitch: CGFloat { railButtonHeight + railButtonSpacing }

    /// Интервал между кнопками рельса при данном числе видимых разделов.
    ///
    /// Выключенные разделы освобождают место, и колонка не сжимается и не
    /// растягивает панель — она дышит: интервал растёт так, чтобы занять ту же
    /// высоту, что у полного рельса, но не дальше потолка — две иконки по
    /// разным углам читались бы не колонкой, а двумя потеряшками.
    static func railSpacing(forVisible count: Int) -> CGFloat {
        guard count > 1 else { return railButtonSpacing }
        let fullHeight = CGFloat(7) * railButtonHeight + 6 * railButtonSpacing
        let stretched = (fullHeight - CGFloat(count) * railButtonHeight) / CGFloat(count - 1)
        return min(max(railButtonSpacing, stretched), 16)
    }

    /// Шаг рельса при данном числе видимых разделов — для пересчёта
    /// перетаскивания в количество пройденных мест.
    static func railPitch(forVisible count: Int) -> CGFloat {
        railButtonHeight + railSpacing(forVisible: count)
    }

    /// Below this the pointer never left the icon, so the press is a click.
    static let railDragThreshold: CGFloat = 4

    // MARK: - Материал

    /// Панель — передняя стенка прибора: графитовый анодированный алюминий.
    /// Тёмный регистр здесь не «тёмная тема», а сам материал: панель свисает
    /// поверх чужих окон, чаще всего тёмных, и светлая плита рядом с ними
    /// читалась бы как чужеродная заплата.
    static let panelTop = Color(red: 0.227, green: 0.231, blue: 0.239)
    static let panelBottom = Color(red: 0.165, green: 0.169, blue: 0.176)
    static let railTop = Color(red: 0.137, green: 0.141, blue: 0.149)
    static let railBottom = Color(red: 0.110, green: 0.114, blue: 0.122)

    /// Утопленная плита: та же поверхность, но вдавленная в панель.
    static let plateTop = Color(red: 0.180, green: 0.184, blue: 0.192)
    static let plateBottom = Color(red: 0.200, green: 0.204, blue: 0.216)

    /// Приподнятая клавиша.
    static let keyTop = Color(red: 0.271, green: 0.275, blue: 0.290)
    static let keyBottom = Color(red: 0.216, green: 0.220, blue: 0.231)

    /// Прорезь под ползунок — самое тёмное место панели.
    static let groove = Color(red: 0.125, green: 0.129, blue: 0.137)

    // MARK: - Свет

    /// Янтарь горящей лампы. Он же заливка главного действия: в приборе
    /// светится ровно то, что сейчас работает.
    static let accent = Color(red: 0.941, green: 0.659, blue: 0.118)
    static let accentDeep = Color(red: 0.784, green: 0.506, blue: 0.082)
    /// Зелёная лампа «в порядке».
    static let success = Color(red: 0.310, green: 0.663, blue: 0.416)
    /// Красная лампа: разрушающее действие.
    static let danger = Color(red: 0.804, green: 0.318, blue: 0.259)

    /// Гравировка. Основная подпись светлая и тёплая, вторичная — приглушённая
    /// того же тона: серого из ниоткуда на приборной панели не бывает.
    static let engraved = Color(red: 0.937, green: 0.914, blue: 0.863)
    static let engravedDim = Color(red: 0.655, green: 0.635, blue: 0.588)
    /// Тонкая риска, которой панель делится на секции.
    static let scribe = Color.white.opacity(0.14)

    /// Знак приложения, заранее уменьшенный до размера, близкого к экранному:
    /// пересчёт с тысячи пикселей на лету рвал край. Читается один раз —
    /// панель перерисовывается часто.
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "LogoSmall", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

// MARK: - Поверхности

/// Отлив шлифованного металла.
///
/// Сначала это были настоящие риски — линии через каждые три пункта. На бумаге
/// приём верный, на экране он превратился в полоски: глаз на таком расстоянии
/// различает каждую и читает их как грязь, а не как фактуру. Настоящий
/// анодированный алюминий с полуметра выглядит иначе — не линиями, а мягкими
/// продольными полосами света, широкими и почти незаметными по отдельности.
/// Здесь ровно они: несколько размытых лент поперёк панели, без единой линии.
struct BrushedFinish: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.000), location: 0.00),
                .init(color: .white.opacity(0.022), location: 0.13),
                .init(color: .black.opacity(0.018), location: 0.27),
                .init(color: .white.opacity(0.016), location: 0.44),
                .init(color: .black.opacity(0.022), location: 0.61),
                .init(color: .white.opacity(0.020), location: 0.78),
                .init(color: .black.opacity(0.014), location: 0.92),
                .init(color: .white.opacity(0.000), location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .allowsHitTesting(false)
    }
}

extension View {
    /// Приподнятая поверхность: светлая кромка сверху, тень снизу.
    func raisedSurface(cornerRadius: CGFloat = 7) -> some View {
        background(
            LinearGradient(
                colors: [CurtyTheme.keyTop, CurtyTheme.keyBottom],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .black.opacity(0.28)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
    }

    /// Утопленная плита: тень падает внутрь, по нижней кромке — блик.
    func recessedPlate(cornerRadius: CGFloat = 10) -> some View {
        background(
            LinearGradient(
                colors: [CurtyTheme.plateTop, CurtyTheme.plateBottom],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.45), .white.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    /// Подсвеченная гравировка: тёплый ореол вокруг светлой буквы.
    func litEngraving(_ strength: Double = 0.22) -> some View {
        shadow(color: CurtyTheme.accent.opacity(strength), radius: 6)
    }
}

/// Подпись, гравированная на панели: прописные, разрежённые, приглушённые.
struct Legend: View {
    let text: String
    var size: CGFloat = 9
    var tint: Color = CurtyTheme.engravedDim

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(tint)
    }
}

/// Лампа-аннунциатор. Горящая светится и отбрасывает ореол, погасшая — тёмное
/// углубление: в приборе выключенное видно так же ясно, как включённое.
struct Lamp: View {
    var isLit: Bool
    var colour: Color = CurtyTheme.accent
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(isLit ? colour : Color.black.opacity(0.55))
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(.white.opacity(isLit ? 0.45 : 0.06), lineWidth: 0.5)
            )
            .shadow(color: isLit ? colour.opacity(0.9) : .clear, radius: isLit ? 5 : 0)
    }
}

// MARK: - Кнопки

/// Главное действие — единственная клавиша, залитая светом.
struct CurtyProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration)
    }

    private struct Rendered: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            let pressed = configuration.isPressed

            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.13, green: 0.10, blue: 0.03))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: pressed
                            ? [CurtyTheme.accentDeep, CurtyTheme.accentDeep]
                            : [CurtyTheme.accent, CurtyTheme.accentDeep],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(pressed ? 0.14 : 0.34), lineWidth: 1)
                )
                // Нажатая клавиша уходит внутрь: ореол гаснет, сама клавиша
                // сдвигается на пункт вниз.
                .shadow(
                    color: CurtyTheme.accent.opacity(isHovering && !pressed ? 0.45 : 0.25),
                    radius: pressed ? 0 : 7
                )
                .offset(y: pressed ? 1 : 0)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .saturation(isEnabled ? 1 : 0)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }
    }
}

/// Обычная клавиша: приподнятый металл.
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
            let pressed = configuration.isPressed

            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isDestructive ? CurtyTheme.danger : CurtyTheme.engraved)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .raisedSurface()
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isDestructive
                                ? CurtyTheme.danger.opacity(isHovering ? 0.55 : 0.28)
                                : .white.opacity(isHovering ? 0.22 : 0),
                            lineWidth: 1
                        )
                )
                .brightness(isHovering && !pressed ? 0.05 : 0)
                .offset(y: pressed ? 1 : 0)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }
    }
}

/// Тумблер: клавиша с лампой и словом. Системный NSSwitch рисуется графитом,
/// пока окно не станет ключевым, а панель специально не забирает фокус, —
/// он выглядел бы вечно потухшим. Кнопка, а не жест: так он доступен с
/// клавиатуры и VoiceOver.
struct CurtySwitch: View {
    @Binding var isOn: Bool
    var isEnabled = true

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Lamp(isLit: isOn && isEnabled, size: 6)
                Text(isOn ? "ВКЛ" : "ВЫКЛ")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(isOn ? CurtyTheme.engraved : CurtyTheme.engravedDim)
                    .frame(width: 32, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .raisedSurface(cornerRadius: 6)
            .brightness(isHovering && isEnabled ? 0.05 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .accessibilityValue(isOn ? "включено" : "выключено")
    }
}

// MARK: - Плиты и строки

/// Плита прибора. Имя прежнее — им пользуется полтора десятка мест.
struct CurtyCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recessedPlate()
    }
}

/// Секция с гравированной подписью на кромке — так подписан любой блок
/// приборной панели. Заменяет собой безымянную карточку.
struct CurtySection<Content: View>: View {
    let title: String
    var fillsHeight = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Legend(text: title)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .recessedPlate()
    }
}

/// Строка списка. У выбранной горит лампа на кромке и светлеет поле, под
/// курсором поле светлеет слабее. Ни рамок, ни пунктиров: в приборе состояние
/// показывает свет.
///
/// Нажатие строка принимает сама, всей своей площадью: когда область нажатия
/// висела на внутреннем стеке с текстом, она покрывала полоску в шестнадцать
/// пунктов посреди сорокачетырёхпунктовой строки — клик точно по имени
/// срабатывал, клик на пару пунктов выше или ниже проваливался в поля. При
/// быстром перекликивании рука мажет по вертикали, и это выглядело как
/// «выделение работает через раз».
struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let isHovered: Bool
    /// Вызывается по нажатию в теле строки — см. onLeftMouseDown.
    var onPress: ((NSEvent) -> Void)?
    /// Сколько правого края строки нажатию не принадлежит: там кнопки, и клик
    /// по ним не должен заодно выделять строку. Отступ до кромки строка
    /// добавляет сама — она знает собственные поля.
    var pressExclusionTrailing: CGFloat = 0
    /// Файлы, которые эта строка отдаёт перетаскиванием, если отдаёт.
    var dragSource: (() -> RowDragPayload?)?
    /// Нажатие в строке кончилось щелчком, а не перетаскиванием.
    var onPressEndedWithoutDrag: (() -> Void)?
    @ViewBuilder let content: Content

    private static var horizontalPadding: CGFloat { 8 }

    var body: some View {
        HStack(spacing: 8) {
            Lamp(isLit: isSelected, size: 5)
            content
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.09 : (isHovered ? 0.05 : 0.025)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.16 : 0.05), lineWidth: 1)
        )
        .modifier(RowPressModifier(
            onPress: onPress,
            trailingExclusion: pressExclusionTrailing > 0
                ? pressExclusionTrailing + Self.horizontalPadding
                : 0,
            dragSource: dragSource,
            onPressEndedWithoutDrag: onPressEndedWithoutDrag
        ))
    }
}

private struct RowPressModifier: ViewModifier {
    let onPress: ((NSEvent) -> Void)?
    let trailingExclusion: CGFloat
    let dragSource: (() -> RowDragPayload?)?
    let onPressEndedWithoutDrag: (() -> Void)?

    func body(content: Content) -> some View {
        if let onPress {
            content.onLeftMouseDown(
                trailingExclusion: trailingExclusion,
                dragSource: dragSource,
                onPressEndedWithoutDrag: onPressEndedWithoutDrag,
                perform: onPress
            )
        } else {
            content
        }
    }
}

/// Пустое состояние: не провал в панели, а погашенный её участок — вычерченная
/// рамка, приглушённый знак и одна строка о том, что этот блок зажжёт.
struct DrawnEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CurtyTheme.engravedDim)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CurtyTheme.engraved)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(CurtyTheme.engravedDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .recessedPlate()
    }
}

/// Секция списка во всю доступную высоту: у прибора нет полупустых блоков,
/// границы у каждого свои независимо от того, сколько внутри строк.
struct CurtyListPane<Content: View>: View {
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let footer {
                Rectangle().fill(CurtyTheme.scribe).frame(height: 1)
                Legend(text: footer, size: 8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .recessedPlate()
    }
}

/// Полоса управления над списком.
struct CurtyStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .recessedPlate(cornerRadius: 8)
    }
}

// MARK: - Подтверждение

/// Клавиша разрушающего действия: та же форма, что у главной, но залита
/// красным. В приборе цвет здесь не украшение — это лампа аварии.
struct CurtyDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rendered(configuration: configuration)
    }

    private struct Rendered: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            let pressed = configuration.isPressed

            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.92))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [CurtyTheme.danger, CurtyTheme.danger.opacity(0.78)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(isHovering ? 0.5 : 0.3), lineWidth: 1)
                )
                .shadow(color: CurtyTheme.danger.opacity(pressed ? 0 : (isHovering ? 0.55 : 0.3)), radius: 7)
                .offset(y: pressed ? 1 : 0)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }
        }
    }
}

/// Съёмная плита с вопросом, лежащая поверх погашенной панели. Системный
/// `confirmationDialog` оформить нельзя — его рисует macOS, и посреди
/// графита он выглядел чужой белой карточкой.
struct CurtyConfirmationPlate: View {
    let confirmation: PendingConfirmation
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Панель гаснет, но не прячется: человек видит, к чему вопрос.
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 9) {
                Text(confirmation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CurtyTheme.engraved)
                    .fixedSize(horizontal: false, vertical: true)

                Text(confirmation.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(CurtyTheme.engravedDim)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    Spacer(minLength: 0)
                    Button("Отмена", action: onDismiss)
                        .buttonStyle(CurtySecondaryButtonStyle())
                    Button(confirmation.actionTitle) {
                        confirmation.perform()
                        onDismiss()
                    }
                    .buttonStyle(CurtyDangerButtonStyle())
                }
                .padding(.top, 3)
            }
            .padding(16)
            .frame(width: 296)
            .background(
                LinearGradient(
                    colors: [CurtyTheme.keyTop, CurtyTheme.keyBottom],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .black.opacity(0.35)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
        }
    }
}

// MARK: - Строки состояния

/// Ошибку записи некуда деть, кроме экрана: без неё пользователь узнаёт о
/// потерянной заметке через часы, когда восстанавливать уже нечего.
struct CurtyErrorRow: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Lamp(isLit: true, colour: CurtyTheme.danger, size: 7)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(CurtyTheme.engraved)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let onDismiss {
                CurtyRowButton(systemName: "xmark", title: "Скрыть сообщение", size: 20, glyphSize: 10, action: onDismiss)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CurtyTheme.danger.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CurtyTheme.danger.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Окно отмены удаления. Живёт несколько секунд и исчезает само.
struct CurtyUndoBar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CurtyTheme.accent)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(CurtyTheme.engraved)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Отменить", action: onUndo)
                .buttonStyle(CurtySecondaryButtonStyle())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .recessedPlate(cornerRadius: 8)
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

    private var tint: Color {
        if isConfirming { return CurtyTheme.success }
        guard isEnabled else { return CurtyTheme.engravedDim }
        if isDestructive { return isLit ? CurtyTheme.danger : CurtyTheme.engravedDim }
        return isLit ? CurtyTheme.accent : CurtyTheme.engravedDim
    }

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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(isLit || isConfirming ? 0.08 : 0))
                )
                .shadow(color: tint.opacity(isLit || isConfirming ? 0.35 : 0), radius: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
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
}

/// Какую строку подсветить галочкой и каким по счёту разом. Одно и то же
/// действие вызывают и кнопка, и ⌘C, а повторное копирование того же элемента
/// должно подтверждаться заново — поэтому новый токен на каждое нажатие.
struct RowCopyConfirmation: Equatable {
    let itemID: UUID
    let token: UUID

    init(_ itemID: UUID) {
        self.itemID = itemID
        token = UUID()
    }

    func token(for id: UUID) -> UUID? { itemID == id ? token : nil }
}

// MARK: - Поля ввода

/// Окно ввода вырезано в панели: тень падает внутрь, а в фокусе по кромке
/// зажигается тонкая янтарная линия — то же, что делает подсветка шкалы.
/// Системная обводка фокуса синяя и к прибору отношения не имеет.
private struct CurtyFieldChrome: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(CurtyTheme.groove)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? CurtyTheme.accent.opacity(0.7) : .black.opacity(0.5),
                        lineWidth: 1
                    )
            )
            .shadow(color: CurtyTheme.accent.opacity(isFocused ? 0.25 : 0), radius: 5)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

extension View {
    func curtyFieldChrome(isFocused: Bool, cornerRadius: CGFloat = 7) -> some View {
        modifier(CurtyFieldChrome(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

/// Hover feedback for controls that draw themselves — switches above all —
/// where a background of our own cannot be slipped underneath.
private struct CurtyHoverLift: ViewModifier {
    var scale: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovering ? 0.06 : 0)
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

// MARK: - Нажатие в строках списков

extension View {
    /// Действие по нажатию кнопки мыши — в обход жестов SwiftUI.
    ///
    /// Жестам в строках списков верить нельзя, это проверено замером по
    /// журналу панели: нажатие доходило до окна всегда, а распознаватели —
    /// что одиночного щелчка, что перетаскивания с нулевым порогом —
    /// срабатывали меньше чем в половине случаев. Кнопки SwiftUI при этом
    /// работали без осечек.
    ///
    /// Обычный путь AppKit тоже закрыт: свой NSView под строкой до mouseDown
    /// не доходит — обёртка, в которую SwiftUI заворачивает чужие виды,
    /// гасит его ответ на hitTest. Поэтому вид здесь только сообщает свой
    /// прямоугольник, а нажатия раздаёт само окно панели: оно видит каждое
    /// событие в sendEvent и передаёт его вью, в чей прямоугольник пришёлся
    /// щелчок. См. RowPressRouter.
    ///
    /// Выделение по нажатию — а не по завершённому щелчку — это заодно и
    /// поведение Finder.
    func onLeftMouseDown(
        trailingExclusion: CGFloat = 0,
        dragSource: (() -> RowDragPayload?)? = nil,
        onPressEndedWithoutDrag: (() -> Void)? = nil,
        onDragChanged: ((CGFloat) -> Void)? = nil,
        onDragEnded: (() -> Void)? = nil,
        perform action: @escaping (NSEvent) -> Void
    ) -> some View {
        background(LeftMouseDownCatcher(
            action: action,
            trailingExclusion: trailingExclusion,
            dragSource: dragSource,
            onPressEndedWithoutDrag: onPressEndedWithoutDrag,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        ))
    }

    /// Прорезь поля целиком принимает нажатие.
    ///
    /// У плоского TextField кликабельна лишь строка текста, а прорезь шире неё
    /// на поля. Клик по самому тексту это правило не трогает — им занимается
    /// система. Клик по полям прорези находит текстовый вид над подложкой и
    /// делает его первым ответчиком — оборотом цикла позже, когда щелчок
    /// дообработан и уже некому увести фокус.
    func curtyFieldPressFocus() -> some View {
        background(LeftMouseDownCatcher(
            action: { _ in },
            trailingExclusion: 0,
            dragSource: nil,
            onPressEndedWithoutDrag: nil,
            focusesFieldOutsideText: true
        ))
    }
}

/// Файлы, которые отдаёт строка, и право на них: тащат строку из выделения —
/// едет всё выделение.
///
/// Право приходится держать открытым всё перетаскивание: полка владеет чужими
/// файлами по закладке, а система выдаёт доступ приёмнику, только пока он
/// открыт у источника. Закрывает его `release`, когда сессия закончилась.
struct RowDragPayload {
    let urls: [URL]
    let release: () -> Void

    /// Сколько право живёт после того, как перетаскивание закончилось.
    /// Достаточно, чтобы приёмник успел прочитать файл и, если ему нужно,
    /// сделать свою копию; и мало, чтобы чужой файл не оставался открытым.
    static let accessWindow: TimeInterval = 60
}

/// Раздаёт нажатия зарегистрированным областям строк по координатам окна.
/// Окно зовёт route из sendEvent на каждый левый mouseDown.
@MainActor
final class RowPressRouter {
    static let shared = RowPressRouter()

    private struct Entry {
        weak var view: LeftMouseDownCatcher.CatcherView?
    }

    private var entries: [Entry] = []

    fileprivate func register(_ view: LeftMouseDownCatcher.CatcherView) {
        entries.removeAll { $0.view == nil || $0.view === view }
        entries.append(Entry(view: view))
    }

    fileprivate func unregister(_ view: LeftMouseDownCatcher.CatcherView) {
        entries.removeAll { $0.view == nil || $0.view === view }
    }

    /// Строка, с которой началось нажатие, и точка начала: если курсор
    /// сдвинется достаточно далеко, это перетаскивание.
    private var pressed: (view: LeftMouseDownCatcher.CatcherView, origin: NSPoint)?

    /// Ниже этого смещения нажатие остаётся нажатием, а не перетаскиванием.
    private static let dragThreshold: CGFloat = 4

    /// Панель умеет накрываться модальной плитой — вопросом подтверждения, —
    /// но роутер слоёв не видит: он раздаёт нажатия по прямоугольникам, и
    /// клик по плите доставался бы строке под ней. О модальности ему сообщает
    /// одно правило снаружи — вместо guard, который приходилось копировать в
    /// каждую вьюху со строками и который в четырёх копиях уже разъезжался.
    var isBlocked: @MainActor () -> Bool = { false }

    /// Отдаёт событие области, в которую пришлось нажатие. Событие не
    /// поглощается — окно продолжит обычную доставку, чтобы кнопки жили как
    /// жили; область только успевает выделить строку.
    func route(_ event: NSEvent) {
        guard !isBlocked() else { return }
        guard let window = event.window else { return }
        let point = event.locationInWindow
        pressed = nil
        // Области накладываются: поле лежит на подложке всей вкладки, которая
        // снимает фокус по пустому месту. Побеждает самая маленькая из
        // накрывших точку — конкретный контрол, а не общий фон.
        var best: LeftMouseDownCatcher.CatcherView?
        var bestArea = CGFloat.greatestFiniteMagnitude
        for entry in entries {
            guard let view = entry.view,
                  view.window === window,
                  !view.isHiddenOrHasHiddenAncestor else { continue }
            var rect = view.convert(view.bounds, to: nil)
            // Правый край строки принадлежит кнопкам: клик по ним не должен
            // заодно выделять строку, которую сам же меняет.
            rect.size.width = max(0, rect.width - view.trailingExclusion)
            guard rect.contains(point) else { continue }
            let area = rect.width * rect.height
            if area < bestArea {
                best = view
                bestArea = area
            }
        }
        guard let best else { return }
        best.action(event)
        if best.focusesFieldOutsideText {
            // После sendEvent: сам щелчок успевает подвигать первого
            // ответчика, ставить своего надо после.
            DispatchQueue.main.async { [weak best] in
                best?.focusFieldIfPressedPadding(at: point)
            }
        }
        if best.dragSource != nil || best.onPressEndedWithoutDrag != nil
            || best.onDragChanged != nil {
            pressed = (best, point)
        }
    }

    /// Перетаскивание начинает сам AppKit, а не SwiftUI. У `.onDrag` иначе:
    /// он копирует файл в кэш нашего контейнера и отдаёт приёмнику путь туда —
    /// путь в чужую песочницу, до которого другому приложению не дотянуться.
    /// Замер приёмником в песочнице показал это дословно, и обойти поведение
    /// средствами SwiftUI не вышло: ссылка на доске возвращала копию обратно.
    func routeDrag(_ event: NSEvent) {
        guard let pressed else { return }

        // Непрерывное перетаскивание — например, строк в плите разделов.
        // Жестам SwiftUI такое доверить нельзя: в этой панели они отдают
        // события с пропусками, и строка догоняла курсор рывками. Роутер видит
        // каждое движение. Координаты окна растут вверх, перевод для вида —
        // вниз, поэтому знак перевёрнут.
        if let onDragChanged = pressed.view.onDragChanged {
            onDragChanged(pressed.origin.y - event.locationInWindow.y)
            return
        }

        let moved = hypot(
            event.locationInWindow.x - pressed.origin.x,
            event.locationInWindow.y - pressed.origin.y
        )
        guard moved > Self.dragThreshold else { return }
        self.pressed = nil
        pressed.view.beginFileDrag(with: event)
    }

    /// Нажатие закончилось, ничего не сдвинув: это был щелчок. Строке есть
    /// что доделать — например, схлопнуть выделение, отложенное на нажатии.
    func routeRelease() {
        pressed?.view.onDragEnded?()
        pressed?.view.onPressEndedWithoutDrag?()
        pressed = nil
    }
}

/// Обещание файла и ссылка на него — на одной доске.
///
/// Порознь не работает ни то, ни другое. Ссылку CapCut принимает, но прочитать
/// не может: он вне песочницы, а файл лежит в «Загрузках», доступ к которым
/// решает системная приватность. Одно обещание он не понимает вовсе — молча не
/// берёт ничего. Finder понимает оба. Поэтому кладём оба и оставляем выбор
/// приёмнику.
private final class FilePromiseWithURL: NSFilePromiseProvider {
    var fileURL: URL?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .fileURL else { return super.pasteboardPropertyList(forType: type) }
        return fileURL?.absoluteString
    }
}

extension LeftMouseDownCatcher.CatcherView: NSFilePromiseProviderDelegate {
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        (filePromiseProvider.userInfo as? URL)?.lastPathComponent ?? "файл"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo destination: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let source = filePromiseProvider.userInfo as? URL else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            // Право на чужой файл открыто на время сессии, но копирование
            // может начаться и позже — открываем ещё раз, это дёшево.
            let opened = source.startAccessingSecurityScopedResource()
            defer { if opened { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.promiseQueue
    }
}

private struct LeftMouseDownCatcher: NSViewRepresentable {
    let action: (NSEvent) -> Void
    let trailingExclusion: CGFloat
    let dragSource: (() -> RowDragPayload?)?
    let onPressEndedWithoutDrag: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var focusesFieldOutsideText = false

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView(
            action: action,
            trailingExclusion: trailingExclusion,
            dragSource: dragSource,
            onPressEndedWithoutDrag: onPressEndedWithoutDrag,
            focusesFieldOutsideText: focusesFieldOutsideText
        )
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
        view.trailingExclusion = trailingExclusion
        view.dragSource = dragSource
        view.onPressEndedWithoutDrag = onPressEndedWithoutDrag
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.focusesFieldOutsideText = focusesFieldOutsideText
    }

    final class CatcherView: NSView, NSDraggingSource {
        var action: (NSEvent) -> Void
        var trailingExclusion: CGFloat
        var dragSource: (() -> RowDragPayload?)?
        var onPressEndedWithoutDrag: (() -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?
        var focusesFieldOutsideText: Bool
        /// Право на файлы, открытое на время сессии. nonisolated(unsafe) —
        /// только ради deinit: тот не изолирован, а право обязано закрыться,
        /// даже если вид умер раньше конца сессии. Пишется всегда на главном.
        nonisolated(unsafe) private var access: (() -> Void)?

        init(
            action: @escaping (NSEvent) -> Void,
            trailingExclusion: CGFloat,
            dragSource: (() -> RowDragPayload?)?,
            onPressEndedWithoutDrag: (() -> Void)?,
            focusesFieldOutsideText: Bool = false
        ) {
            self.action = action
            self.trailingExclusion = trailingExclusion
            self.dragSource = dragSource
            self.onPressEndedWithoutDrag = onPressEndedWithoutDrag
            self.focusesFieldOutsideText = focusesFieldOutsideText
            super.init(frame: .zero)
        }

        deinit {
            // Обычно право закрывает конец сессии перетаскивания; вид,
            // умерший раньше него, не должен унести открытое право с собой.
            access?()
        }

        /// Клик в поля прорези — фокус текстовому виду над подложкой. Клик по
        /// самой текстовой зоне не трогаем: им занимается система, и второй
        /// желающий устроил бы гонку за фокус.
        func focusFieldIfPressedPadding(at pointInWindow: NSPoint) {
            guard let window, let root = window.contentView else { return }
            let myRect = convert(bounds, to: nil)
            var best: NSView?
            var bestArea = CGFloat.greatestFiniteMagnitude
            func walk(_ view: NSView) {
                for sub in view.subviews { walk(sub) }
                guard view is NSTextField || view is NSTextView else { return }
                let rect = view.convert(view.bounds, to: nil)
                guard rect.intersects(myRect) else { return }
                let area = rect.width * rect.height
                if area < bestArea {
                    best = view
                    bestArea = area
                }
            }
            walk(root)
            guard let best else { return }
            let textRect = best.convert(best.bounds, to: nil)
            guard !textRect.contains(pointInWindow) else { return }
            window.makeFirstResponder(best)
        }

        /// Файл отдаётся обещанием: приёмник просит систему, и она кладёт
        /// копию туда, где у него доступ заведомо есть.
        ///
        /// Отдавать настоящий путь оказалось мало. Право, которое система
        /// выдаёт приёмнику при броске, действует для приложений в песочнице —
        /// пробный приёмник читал файл без запинки. А CapCut работает вне
        /// песочницы: там доступ к «Загрузкам» решает системная приватность, и
        /// выдать её из приложения нельзя. Файл он принимал, имя показывал
        /// верное — и писал «файл недоступен». Обещание снимает вопрос: копию
        /// делает сам приёмник у себя.
        func beginFileDrag(with event: NSEvent) {
            guard let payload = dragSource?(), !payload.urls.isEmpty else { return }
            access?()
            access = payload.release

            let point = convert(event.locationInWindow, from: nil)
            let size = NSSize(width: 48, height: 48)
            // Значки ложатся стопкой с лёгким сдвигом: видно, что едет пачка.
            let items = payload.urls.enumerated().map { index, url in
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                let promise = FilePromiseWithURL(fileType: type.identifier, delegate: self)
                promise.userInfo = url
                promise.fileURL = url
                let item = NSDraggingItem(pasteboardWriter: promise)
                let shift = CGFloat(min(index, 4)) * 4
                item.setDraggingFrame(
                    NSRect(
                        x: point.x - size.width / 2 + shift,
                        y: point.y - size.height / 2 - shift,
                        width: size.width, height: size.height
                    ),
                    contents: NSWorkspace.shared.icon(forFile: url.path)
                )
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        // MARK: Обещание файла

        /// Копирование идёт не на главной очереди: файл может быть большим, а
        /// панель в это время обязана оставаться живой.
        private static let promiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.name = "dev.curty.file-promise"
            queue.qualityOfService = .userInitiated
            return queue
        }()

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            // Право снимается не сразу. Приёмник читает файл не в момент
            // броска, а когда дойдут руки: CapCut строит превью уже после — и
            // на закрытом праве показывал «файл недоступен», хотя сам файл
            // принял и имя показывал верное. Наш пробный приёмник читает
            // мгновенно и потому не замечал разницы.
            let release = access
            access = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + RowDragPayload.accessWindow) {
                release?()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                RowPressRouter.shared.unregister(self)
            } else {
                RowPressRouter.shared.register(self)
            }
        }
    }
}
