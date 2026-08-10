import SwiftUI

struct SnippetsView: View {
    @ObservedObject var store: SnippetStore
    @State private var draft: SnippetDraft?
    @State private var selectedID: UUID?
    @State private var copyConfirmation: RowCopyConfirmation?
    /// Поиск живёт в том же окне, что и кнопка с ⌘C, и сочетание достанется
    /// ей, а не полю. Пока курсор в поиске, копирование сниппета выключено.
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            content

            if let pending = store.pendingDeletion {
                CurtyUndoBar(message: "Сниппет удалён") { store.undoDeletion() }
                    .id(pending.item.id)
            }

            if let error = store.lastError {
                CurtyErrorRow(message: error) { store.lastError = nil }
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.pendingDeletion)
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack {
                // Системное поле приносит с собой синюю обводку фокуса, которая
                // не имеет отношения к остальному оформлению панели. Рамку
                // рисуем сами и подсвечиваем акцентом, когда курсор в поле.
                TextField("Поиск сниппетов", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.primary.opacity(isSearchFocused ? 0.09 : 0.055))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isSearchFocused ? CurtyTheme.accent : .primary.opacity(0.10),
                                lineWidth: isSearchFocused ? 1.5 : 1
                            )
                    )
                    .focused($isSearchFocused)
                    .focusEffectDisabled()
                    .animation(.easeOut(duration: 0.14), value: isSearchFocused)

                Button { draft = SnippetDraft(source: nil) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(CurtyProminentButtonStyle())
                .curtyHoverLift(scale: 1.08)
                .help("Новый сниппет")
            }
            if store.filteredItems.isEmpty {
                CurtyCard {
                    VStack(spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 26, weight: .light))
                        Text(store.query.isEmpty ? "Здесь будет ваш часто используемый текст" : "Ничего не найдено")
                            .font(.system(size: 13, weight: .medium))
                        Text("Сниппеты хранятся локально.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.filteredItems) { snippet in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snippet.title.isEmpty ? "Без названия" : snippet.title)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(snippet.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                HStack(spacing: CurtyTheme.rowActionSpacing) {
                                    CurtyRowButton(
                                        systemName: "pencil",
                                        title: "Изменить сниппет",
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13
                                    ) { draft = SnippetDraft(source: snippet) }
                                    CurtyRowButton(
                                        systemName: "doc.on.doc",
                                        title: "Копировать текст (⌘C)",
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13,
                                        confirmsWith: "checkmark",
                                        confirmationToken: copyConfirmation?.token(for: snippet.id)
                                    ) { store.copy(snippet) }

                                    Spacer().frame(width: CurtyTheme.rowActionDestructiveGap)

                                    CurtyRowButton(
                                        systemName: "trash",
                                        title: "Удалить сниппет",
                                        isDestructive: true,
                                        size: CurtyTheme.rowActionSize,
                                        glyphSize: 13
                                    ) { store.remove(snippet) }
                                }
                                .frame(width: CurtyTheme.rowActionClusterWidth, alignment: .trailing)
                            }
                            .padding(10)
                            .background(background(for: snippet.id), in: RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(selectedID == snippet.id ? CurtyTheme.accent.opacity(0.55) : .clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedID = snippet.id
                                // Клик по строке не уводит фокус из поля поиска
                                // сам по себе, а без этого ⌘C останется выключен.
                                isSearchFocused = false
                            }
                        }
                    }
                }
            }
        }
        // ⌘C копирует выделенный сниппет — то же, что кнопка в строке.
        // Сочетание держит кнопка, а не обработчик нажатий: события с Command
        // приходят в окно как key equivalent и до onKeyPress не доходят.
        .background {
            Button("Копировать выделенный сниппет") { copySelected() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectedSnippet == nil || isSearchFocused)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Клик мимо поля снимает с него фокус — иначе рамка остаётся
        // подсвеченной, и непонятно, куда попадёт следующее нажатие клавиш.
        // Строки и кнопки обрабатывают нажатие сами, сюда доходит только то,
        // что пришлось на пустое место.
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        .sheet(item: $draft) { target in
            SnippetEditor(
                heading: target.source == nil ? "Новый сниппет" : "Изменить сниппет",
                title: target.source?.title ?? "",
                body: target.source?.body ?? "",
                onSave: { title, body in
                    if let source = target.source {
                        store.update(source, title: title, body: body)
                    } else {
                        store.add(title: title, body: body)
                    }
                    draft = nil
                },
                onCancel: { draft = nil }
            )
        }
    }

    private var selectedSnippet: Snippet? {
        store.filteredItems.first { $0.id == selectedID }
    }

    private func copySelected() {
        guard let snippet = selectedSnippet else { return }
        store.copy(snippet)
        copyConfirmation = RowCopyConfirmation(snippet.id)
    }

    private func background(for id: UUID) -> Color {
        selectedID == id ? CurtyTheme.accent.opacity(0.16) : .primary.opacity(0.045)
    }
}

private struct SnippetDraft: Identifiable {
    let id = UUID()
    let source: Snippet?
}

private struct SnippetEditor: View {
    let heading: String
    @State private var title: String
    @State private var text: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    init(
        heading: String,
        title: String,
        body: String,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.heading = heading
        _title = State(initialValue: title)
        _text = State(initialValue: body)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            TextField("Название", text: $title)
            TextEditor(text: $text)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Button("Отмена", action: onCancel)
                Spacer()
                Button("Сохранить") { onSave(title, text) }
                    .buttonStyle(CurtyProminentButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
