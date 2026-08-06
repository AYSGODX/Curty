import SwiftUI

struct NotesView: View {
    @ObservedObject var store: NoteStore

    private var selectedNote: ScratchNote? {
        store.items.first { $0.id == store.selectedID }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                Button { store.add() } label: {
                    Label("Новая", systemImage: "plus")
                }
                .buttonStyle(CurtyProminentButtonStyle())
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
                                    .background(
                                        store.selectedID == note.id ? CurtyTheme.accent.opacity(0.16) : .primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                            }
                            .buttonStyle(.plain)
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
                            Button { store.remove(note) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Удалить заметку")
                        }
                        TextEditor(text: Binding(
                            get: { note.text },
                            set: { store.update(note.id, text: $0) }
                        ))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 132)
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
