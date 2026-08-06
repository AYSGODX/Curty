import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(
                    store.isMonitoring ? "Наблюдение включено" : "Наблюдение приостановлено",
                    systemImage: store.isMonitoring ? "record.circle" : "pause.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(store.isMonitoring ? CurtyTheme.success : .secondary)
                Spacer()
                if !store.entries.isEmpty {
                    Button("Очистить") { store.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("", isOn: $preferences.clipboardMonitoringEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(CurtyTheme.accent)
                    .accessibilityLabel("Наблюдение за буфером обмена")
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
                                Spacer()
                                Button { store.copy(entry) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain)
                                    .help("Копировать")
                                if case .image = entry.payload {
                                    Button { store.saveImage(entry) } label: { Image(systemName: "tray.and.arrow.down") }
                                        .buttonStyle(.plain)
                                        .help("Сохранить на полку")
                                        .accessibilityLabel("Сохранить изображение на полку")
                                }
                                Button { store.remove(entry) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .help("Удалить")
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
