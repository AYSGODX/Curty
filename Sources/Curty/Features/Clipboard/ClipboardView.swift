import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var model: AppModel
    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var copyConfirmation: RowCopyConfirmation?

    var body: some View {
        VStack(spacing: 12) {
            CurtyStrip {
            HStack(spacing: 8) {
                // The switch belongs next to the state it controls: sitting by
                // "Очистить" it read as that button's switch.
                CurtySwitch(isOn: $preferences.clipboardMonitoringEnabled)
                    .curtyHoverLift(scale: 1.06)
                    .accessibilityLabel("Наблюдение за буфером обмена")
                    .help(store.isMonitoring ? "Приостановить наблюдение" : "Возобновить наблюдение")

                Label(
                    store.isMonitoring ? "Наблюдение включено" : "Наблюдение приостановлено",
                    systemImage: store.isMonitoring ? "record.circle" : "pause.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(store.isMonitoring ? CurtyTheme.success : CurtyTheme.engravedDim)
                .lineLimit(1)

                Spacer(minLength: 8)

                if !store.entries.isEmpty {
                    Button {
                        model.confirm(
                            "Очистить историю буфера?",
                            detail: "История хранится только в памяти, восстановить её будет нельзя.",
                            actionTitle: "Очистить"
                        ) { store.clear() }
                    } label: {
                        Label("Очистить", systemImage: "trash")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(CurtySecondaryButtonStyle())
                    .curtyHoverLift()
                    .help("Очистить историю буфера")
                }
            }
            }

            // Images are opt-in, and with them off nothing about the clipboard
            // screen says so — it just never shows a picture, which reads as
            // broken rather than switched off.
            if store.isMonitoring, !preferences.clipboardImagesEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(CurtyTheme.accent)
                    Text("Изображения не попадают в историю")
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button("Включить") { preferences.clipboardImagesEnabled = true }
                        .buttonStyle(CurtySecondaryButtonStyle())
                        .curtyHoverLift()
                        .help("Превью будут храниться в памяти; на полку они попадают только по отдельному нажатию")
                }
                .font(.caption)
                .foregroundStyle(CurtyTheme.engravedDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if store.entries.isEmpty {
                DrawnEmptyState(
                    icon: store.isMonitoring ? "doc.on.clipboard" : "hand.raised.fill",
                    title: store.isMonitoring ? "История пуста" : "Наблюдение выключено",
                    detail: store.isMonitoring
                        ? "Скопируйте что-нибудь — запись появится здесь.\nИстория живёт только в памяти."
                        : "Включите тумблер слева,\nкогда история понадобится."
                )
            } else {
                CurtyListPane(footer: "записей \(store.entries.count)") {
                    LazyVStack(spacing: 5) {
                        ForEach(store.entries) { entry in
                            SelectableRow(
                                isSelected: selectedID == entry.id,
                                isHovered: hoveredID == entry.id,
                                onPress: { _ in
                                    // Сквозь плиту подтверждения не выделять:
                                    // нажатия раздаются по прямоугольникам.
                                    guard model.pendingConfirmation == nil else { return }
                                    selectedID = entry.id
                                },
                                pressExclusionTrailing: CurtyTheme.rowActionClusterWidth
                            ) {
                            HStack(spacing: 9) {
                                HStack(spacing: 9) {
                                    Image(systemName: entry.symbol)
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(width: 20)
                                        .foregroundStyle(CurtyTheme.engravedDim)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.preview)
                                            .font(.system(size: 12))
                                            .foregroundStyle(CurtyTheme.engraved)
                                            .lineLimit(2)
                                        Text(entry.capturedAt, style: .time)
                                            .font(.system(size: 10).monospacedDigit())
                                            .foregroundStyle(CurtyTheme.engravedDim)
                                    }
                                    Spacer(minLength: 6)
                                }
                                HStack(spacing: CurtyTheme.rowActionSpacing) {
                                    // Галочки подтверждения у переноса нет
                                    // намеренно: строка сама исчезает из
                                    // истории, и это ответ понятнее любого
                                    // значка.
                                    switch entry.payload {
                                    case .image:
                                        CurtyRowButton(
                                            systemName: "tray.and.arrow.down",
                                            title: "Перенести изображение на полку",
                                            size: CurtyTheme.rowActionSize,
                                            glyphSize: 13
                                        ) { store.saveImage(entry) }
                                    case .file:
                                        CurtyRowButton(
                                            systemName: "tray.and.arrow.down",
                                            title: "Перенести файл на полку",
                                            size: CurtyTheme.rowActionSize,
                                            glyphSize: 13
                                        ) { store.saveFile(entry) }
                                    case .text:
                                        EmptyView()
                                    }
                                    CurtyRowButton(
                                        systemName: "doc.on.doc",
                                        title: "Вернуть в буфер обмена (⌘C)",
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13,
                                        confirmsWith: "checkmark",
                                        confirmationToken: copyConfirmation?.token(for: entry.id)
                                    ) { store.copy(entry) }

                                    Spacer().frame(width: CurtyTheme.rowActionDestructiveGap)

                                    CurtyRowButton(
                                        systemName: "xmark",
                                        title: "Убрать из истории",
                                        isDestructive: true,
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13
                                    ) { store.remove(entry) }
                                }
                                .frame(width: CurtyTheme.rowActionClusterWidth, alignment: .trailing)
                            }
                            }
                            .onHover { hovering in
                                if hovering {
                                    hoveredID = entry.id
                                } else if hoveredID == entry.id {
                                    hoveredID = nil
                                }
                            }
                        }
                    }
                }
            }

            if let error = store.lastError {
                CurtyErrorRow(message: error) { store.lastError = nil }
            }
        }
        // ⌘C возвращает выделенную запись в буфер — то же, что кнопка в строке.
        // Сочетание держит кнопка, а не обработчик нажатий: события с Command
        // приходят в окно как key equivalent и до onKeyPress не доходят.
        .background {
            Button("Вернуть выделенное в буфер") { copySelected() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectedEntry == nil)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Шторка закрылась — выделение теряет смысл: фокус ушёл, и при
        // следующем раскрытии подсвеченная строка обещает то, чего нет.
        .onChange(of: model.isPanelOpen) { _, isOpen in
            if !isOpen { selectedID = nil }
        }

    }

    private var selectedEntry: ClipboardEntry? {
        store.entries.first { $0.id == selectedID }
    }

    private func copySelected() {
        guard let entry = selectedEntry else { return }
        store.copy(entry)
        copyConfirmation = RowCopyConfirmation(entry.id)
    }

}
