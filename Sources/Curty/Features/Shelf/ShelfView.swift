import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: AppModel
    @State private var pendingExecutable: ShelfItem?
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 12) {
            // "Добавить" sits on the left because the right-hand slot is where
            // Буфер keeps its "Очистить"; a button that changes meaning when you
            // switch tabs is a button you eventually misclick.
            HStack(spacing: 8) {
                Button("Добавить", systemImage: "plus") { chooseFiles() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(CurtyTheme.accent)
                    .curtyHoverLift()

                Text("Элементов: \(store.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if !store.items.isEmpty {
                    Button {
                        isConfirmingClear = true
                    } label: {
                        Label("Очистить", systemImage: "trash")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .curtyHoverLift()
                    .help("Убрать все файлы с полки")
                }
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
                                Spacer(minLength: 6)
                                // Kept as one tight cluster: spread across the
                                // row's own spacing they were eating the width
                                // the file name needs.
                                HStack(spacing: 0) {
                                    CurtyRowButton(
                                        systemName: "arrow.up.forward.app",
                                        title: "Открыть файл"
                                    ) { requestOpen(item) }
                                    CurtyRowButton(
                                        systemName: "doc.on.doc",
                                        title: "Копировать файл"
                                    ) { store.copy(item) }
                                    CurtyRowButton(
                                        systemName: "magnifyingglass",
                                        title: "Показать в Finder"
                                    ) { revealInFinder(item) }
                                    CurtyRowButton(
                                        systemName: "xmark",
                                        title: "Убрать с полки",
                                        isDestructive: true
                                    ) { store.remove(item) }
                                }
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
                if store.open(item, allowingExecutables: true) {
                    model.requestPanelClose()
                }
                pendingExecutable = nil
            }
            Button("Отмена", role: .cancel) { pendingExecutable = nil }
        } message: { item in
            Text("«\(item.name)» может запустить код на этом Mac.")
        }
        .confirmationDialog(
            "Убрать все файлы с полки?",
            isPresented: $isConfirmingClear
        ) {
            Button("Убрать", role: .destructive) { store.clearReferences() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Полка забудет ссылки на файлы. Сами файлы останутся на своих местах.")
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

    /// Finder comes forward as a result of this, so the panel gets out of the
    /// way instead of hovering over what the user was sent to look at.
    private func revealInFinder(_ item: ShelfItem) {
        store.reveal(item)
        model.requestPanelClose()
    }

    /// Opening hands the file to another app, so the panel steps aside — but
    /// only once the file actually opened, never when the attempt was refused.
    private func requestOpen(_ item: ShelfItem) {
        if item.isPotentiallyExecutable {
            pendingExecutable = item
        } else if store.open(item) {
            model.requestPanelClose()
        }
    }
}
