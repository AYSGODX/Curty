import AppKit
import SwiftUI
import XCTest

@testable import Curty

/// Снимает панель во всех разделах, чтобы смотреть на оформление глазами, а не
/// собирать и устанавливать приложение ради каждой правки.
///
/// Обычный прогон тестов ничего не делает: снимок пишется, только если задать
/// каталог в переменной окружения.
///
///     CURTY_SCREENSHOT_DIR=/tmp/curty swift test --filter RendersEveryScreen
///
/// Съёмка идёт через настоящее окно AppKit, а не через ImageRenderer: тот не
/// рисует содержимое прокручиваемых областей — проверено, внутри ScrollView он
/// отдаёт пустоту, и целый раздел настроек выходил чистым листом.
final class ScreenshotRendererTests: XCTestCase {
    @MainActor
    func testRendersEveryScreen() throws {
        guard let directory = ProcessInfo.processInfo.environment["CURTY_SCREENSHOT_DIR"] else {
            throw XCTSkip("CURTY_SCREENSHOT_DIR не задан — снимки не нужны")
        }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for tool in AppModel.Tool.allCases {
                let model = AppModel()
                model.start()
                model.selectedTool = tool
                model.isPanelOpen = true
                // Полоса выреза: на маке с вырезом её сообщает система, здесь
                // задаётся руками, чтобы увидеть вёрстку с отступом.
                if let raw = ProcessInfo.processInfo.environment["CURTY_NOTCH_INSET"],
                   let inset = Double(raw) {
                    model.notchInset = CGFloat(inset)
                }
                // Плиту с вопросом иначе не увидеть: её поднимает нажатие,
                // а нажимать в отрисовке некому.
                if ProcessInfo.processInfo.environment["CURTY_CONFIRM"] != nil {
                    model.confirm(
                        "Убрать все файлы с полки?",
                        detail: "Полка забудет ссылки на файлы. Сами файлы останутся на своих местах.",
                        actionTitle: "Убрать"
                    ) {}
                }

                let png = try capture(PanelRootView(model: model), appearance: appearance)
                try png.write(to: url.appendingPathComponent("\(name)-\(tool.rawValue).png"))
            }
        }
    }

    @MainActor
    private func capture(_ view: some View, appearance: NSAppearance.Name) throws -> Data {
        let frame = NSRect(x: 0, y: 0, width: 488, height: 420)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        // Окно нужно вывести: у скрытого окна AppKit не раскладывает вложенные
        // прокручиваемые области, и они снимаются пустыми.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)

        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)

        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
