import AppKit

/// Всё, что Curty кладёт на доску сама, помечается служебным типом, и история
/// буфера такие записи не подбирает. Без метки копирование файла с полки тут же
/// возвращалось в историю новой записью — дубликатом того, что приложение и так
/// хранит, причём вместе с содержимым файла.
enum InternalPasteboard {
    static let markerType = NSPasteboard.PasteboardType("dev.curty.internal")

    static func write(to pasteboard: NSPasteboard = .general, _ body: (NSPasteboard) -> Void) {
        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: markerType)
        body(pasteboard)
    }

    static func containsMarker(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.data(forType: markerType) != nil
    }
}
