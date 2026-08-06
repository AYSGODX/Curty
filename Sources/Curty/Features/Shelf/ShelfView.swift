import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @State private var isImporterPresented = false
    @State private var isDropTarget = false
    @State private var pendingExecutable: ShelfItem?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Элементов: \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Добавить", systemImage: "plus") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(CurtyTheme.accent)
            }

            if store.items.isEmpty {
                CurtyCard {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(CurtyTheme.accent)
                        Text("Временная полка файлов")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Добавьте файлы, чтобы держать локальные ссылки под рукой.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 118)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isPotentiallyExecutable ? "exclamationmark.shield" : "doc")
                                    .foregroundStyle(item.isPotentiallyExecutable ? Color.orange : CurtyTheme.accent)
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Button { requestOpen(item) } label: { Image(systemName: "arrow.up.forward.app") }
                                    .buttonStyle(.plain).help("Открыть")
                                Button { store.copyPath(item) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("Копировать путь")
                                Button { store.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.plain).help("Показать в Finder")
                                Button { store.remove(item) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Удалить")
                            }
                            .padding(10)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                            // Drag the row straight into Finder or another app.
                            // The receiver reads the file with its own access,
                            // so the bookmark scope does not have to stay open.
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                        }
                    }
                }
            }

            if let error = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { store.addUserSelectedFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            store.addUserSelectedFiles(files)
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(CurtyTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(CurtyTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog(
            "Открыть исполняемый файл?",
            isPresented: Binding(
                get: { pendingExecutable != nil },
                set: { if !$0 { pendingExecutable = nil } }
            ),
            presenting: pendingExecutable
        ) { item in
            Button("Открыть «\(item.name)»", role: .destructive) {
                store.open(item, allowingExecutables: true)
                pendingExecutable = nil
            }
            Button("Отмена", role: .cancel) { pendingExecutable = nil }
        } message: { item in
            Text("«\(item.name)» может запустить код на этом Mac.")
        }
    }

    private func requestOpen(_ item: ShelfItem) {
        if item.isPotentiallyExecutable {
            pendingExecutable = item
        } else {
            store.open(item)
        }
    }
}
