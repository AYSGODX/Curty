import SwiftUI

struct NotesView: View {
    @ObservedObject var store: NoteStore
    @State private var hoveredID: UUID?
    @FocusState private var isEditorFocused: Bool
    @FocusState private var isTitleFocused: Bool

    private var selectedNote: ScratchNote? {
        store.items.first { $0.id == store.selectedID }
    }

    var body: some View {
        VStack(spacing: 8) {
            content

            if let pending = store.pendingDeletion {
                CurtyUndoBar(message: "Заметка удалена") { store.undoDeletion() }
                    .id(pending.item.id)
            }

            if let error = store.lastError {
                CurtyErrorRow(message: error) { store.lastError = nil }
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.pendingDeletion)
    }

    /// Появляется только у края: пока до предела далеко, счётчик — лишний шум.
    /// Отбор идёт по длине в байтах — она известна сразу, тогда как подсчёт
    /// символов обходит строку целиком и повторялся бы на каждое нажатие.
    @ViewBuilder
    private func counter(for note: ScratchNote) -> some View {
        if note.text.utf8.count > NoteStore.counterThreshold {
            let count = note.text.count
            let isOverLimit = count > NoteStore.maxCharacters
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                if isOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                }
                Text("\(count.formatted(.number)) / \(NoteStore.maxCharacters.formatted(.number))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(isOverLimit ? .red : .secondary)
            .help(isOverLimit
                  ? "Сверх предела заметка не сохраняется — сократите текст"
                  : "Предел длины заметки")
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                Button { store.add() } label: {
                    Label("Новая", systemImage: "plus")
                }
                .buttonStyle(CurtyProminentButtonStyle())
                .curtyHoverLift(scale: 1.04)
                CurtyListPane(footer: "заметок \(store.items.count)") {
                    VStack(spacing: 5) {
                        ForEach(store.items) { note in
                            SelectableRow(
                                isSelected: store.selectedID == note.id,
                                isHovered: hoveredID == note.id,
                                onPress: { _ in store.selectedID = note.id }
                            ) {
                                Text(note.listLabel)
                                    .font(.system(
                                        size: 11,
                                        weight: note.hasTitle ? .semibold : .regular
                                    ))
                                    .foregroundStyle(CurtyTheme.engraved)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    if hovering {
                                        hoveredID = note.id
                                    } else if hoveredID == note.id {
                                        hoveredID = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 104)

            if let note = selectedNote {
                CurtySection(title: "Заметка", fillsHeight: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            // Заголовок не обязателен: пустое поле оставляет
                            // заметке прежнюю подпись — первые слова текста.
                            // Читается из стора, а не из note, — по той же
                            // причине, что и текст ниже.
                            TextField("Заголовок", text: Binding(
                                get: { store.items.first { $0.id == note.id }?.title ?? "" },
                                set: { store.update(note.id, title: $0) }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .curtyFieldChrome(isFocused: isTitleFocused)
                            // Кликабельна вся прорезь — правило у
                            // curtyFieldPressFocus.
                            .curtyFieldPressFocus()
                            .focused($isTitleFocused)
                            .focusEffectDisabled()

                            CurtyRowButton(
                                systemName: "trash",
                                title: "Удалить заметку",
                                isDestructive: true,
                                size: CurtyTheme.rowActionSize,
                                glyphSize: 13
                            ) { store.remove(note) }
                        }
                        // Читать текст надо из стора, а не из note: та копия
                        // захвачена при отрисовке и отстаёт на одно нажатие.
                        // SwiftUI видел расхождение и переписывал поле целиком,
                        // сбрасывая курсор в конец, — правка в середине текста
                        // была невозможна.
                        TextEditor(text: Binding(
                            get: { store.items.first { $0.id == note.id }?.text ?? "" },
                            set: { store.update(note.id, text: $0) }
                        ))
                        .font(.system(size: 13))
                        // Своя подложка вместо системной, иначе внутри рамки
                        // остаётся прямоугольник чужого цвета.
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(maxHeight: .infinity)
                        .curtyFieldChrome(isFocused: isEditorFocused, cornerRadius: 10)
                        // Поля прорези вокруг текста тоже ставят фокус.
                        .curtyFieldPressFocus()
                        .focused($isEditorFocused)
                        .focusEffectDisabled()

                        counter(for: note)
                    }
                }
            } else {
                DrawnEmptyState(
                    icon: "note.text",
                    title: "Заметок нет",
                    detail: "Нажмите «Новая» слева.\nЗаметки лежат на этом Mac и никуда не уходят."
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
