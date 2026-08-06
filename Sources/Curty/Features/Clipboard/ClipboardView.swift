import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // The switch belongs next to the state it controls: sitting by
                // "Очистить" it read as that button's switch.
                Toggle("", isOn: $preferences.clipboardMonitoringEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(CurtyTheme.accent)
                    .curtyHoverLift(scale: 1.06)
                    .accessibilityLabel("Наблюдение за буфером обмена")
                    .help(store.isMonitoring ? "Приостановить наблюдение" : "Возобновить наблюдение")

                Label(
                    store.isMonitoring ? "Наблюдение включено" : "Наблюдение приостановлено",
                    systemImage: store.isMonitoring ? "record.circle" : "pause.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(store.isMonitoring ? CurtyTheme.success : .secondary)
                .lineLimit(1)

                Spacer(minLength: 8)

                if !store.entries.isEmpty {
                    Button {
                        store.clear()
                    } label: {
                        Label("Очистить", systemImage: "trash")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .curtyHoverLift()
                    .help("Очистить историю буфера")
                }
            }

            if store.entries.isEmpty {
                CurtyCard {
                    VStack(spacing: 9) {
                        Image(systemName: store.isMonitoring ? "doc.on.clipboard" : "hand.raised.fill")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(store.isMonitoring ? CurtyTheme.accent : .secondary)
                        Text(store.isMonitoring ? "Нет сохранённых элементов" : "Доступ к буферу выключен")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.isMonitoring ? "Новые элементы появляются только во время наблюдения." : "Включайте историю только когда она нужна.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 108)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: entry.symbol)
                                    .frame(width: 22)
                                    .foregroundStyle(CurtyTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.preview)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                    Text(entry.capturedAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                HStack(spacing: CurtyTheme.rowActionSpacing) {
                                    if case .image = entry.payload {
                                        CurtyRowButton(
                                            systemName: "tray.and.arrow.down",
                                            title: "Сохранить изображение на полку",
                                            size: CurtyTheme.rowActionSize,
                                            glyphSize: 13,
                                            confirmsWith: "checkmark"
                                        ) { store.saveImage(entry) }
                                    }
                                    CurtyRowButton(
                                        systemName: "doc.on.doc",
                                        title: "Вернуть в буфер обмена",
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13,
                                        confirmsWith: "checkmark"
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
                            .padding(10)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
            }

            if let error = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).lineLimit(1)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }
}
