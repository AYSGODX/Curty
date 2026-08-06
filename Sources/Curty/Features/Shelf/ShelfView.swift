import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: AppModel
    @State private var pendingExecutable: ShelfItem?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Элементов: \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Добавить", systemImage: "plus") { chooseFiles() }
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

    /// SwiftUI's fileImporter opens the dialog without bringing the app forward.
    /// Curty runs in the background, so the dialog appeared behind the frontmost
    /// window and the button looked dead. Driving NSOpenPanel directly lets it
    /// be raised and focused.
    private func chooseFiles() {
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = true
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = true
        dialog.prompt = "Добавить"
        dialog.message = "Выберите файлы для полки Curty"

        model.isPresentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { response in
            MainActor.assumeIsolated {
                model.isPresentingDialog = false
                guard response == .OK else { return }
                store.addUserSelectedFiles(dialog.urls)
            }
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
