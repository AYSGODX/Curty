import SwiftUI

struct NotesView: View {
    @ObservedObject var store: NoteStore
    @State private var hoveredID: UUID?
    @FocusState private var isEditorFocused: Bool

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

    private func background(for id: UUID) -> Color {
        if store.selectedID == id { return CurtyTheme.accent.opacity(0.16) }
        return hoveredID == id ? .primary.opacity(0.10) : .primary.opacity(0.04)
    }

    private var content: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                Button { store.add() } label: {
                    Label("Новая", systemImage: "plus")
                }
                .buttonStyle(CurtyProminentButtonStyle())
                .curtyHoverLift(scale: 1.04)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.items) { note in
                            Button {
                                store.selectedID = note.id
                            } label: {
                                Text(note.text.isEmpty ? "Новая заметка" : note.text)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(background(for: note.id), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
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
            .frame(width: 92)

            CurtyCard {
                if let note = selectedNote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Быстрая заметка")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
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
                        .frame(minHeight: 132)
                        .curtyFieldChrome(isFocused: isEditorFocused, cornerRadius: 10)
                        .focused($isEditorFocused)
                        .focusEffectDisabled()

                        counter(for: note)
                    }
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "note.text")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(CurtyTheme.accent)
                        Text("Создайте локальную заметку")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
