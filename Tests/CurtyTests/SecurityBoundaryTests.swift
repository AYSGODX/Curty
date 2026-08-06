import AppKit
import XCTest
@testable import Curty
import CurtyShared

final class SecurityBoundaryTests: XCTestCase {
    func testMeetingLinksRequireHTTPSAndApprovedHost() {
        XCTAssertNotNil(MeetingURLPolicy.validate(URL(string: "https://meet.google.com/abc-defg-hij")!))
        XCTAssertNotNil(MeetingURLPolicy.validate(URL(string: "https://subdomain.zoom.us/j/123")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "http://meet.google.com/abc")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "file:///Applications/Calculator.app")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "https://meet.google.com.evil.example/abc")!))
        XCTAssertNil(MeetingURLPolicy.validate(URL(string: "https://user:password@zoom.us/j/123")!))
    }

    func testMeetingDetectorSkipsUnknownLinks() {
        let text = "Agenda https://evil.example/phish then https://teams.microsoft.com/l/meetup-join/123"
        XCTAssertEqual(MeetingURLPolicy.firstApprovedURL(in: text)?.host, "teams.microsoft.com")
    }

    func testClipboardSensitiveTypesAreIgnored() {
        XCTAssertTrue(ClipboardPolicy.shouldIgnore(typeNames: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardPolicy.shouldIgnore(typeNames: ["org.nspasteboard.TransientType"]))
        XCTAssertFalse(ClipboardPolicy.shouldIgnore(typeNames: ["public.utf8-plain-text"]))
    }

    func testClipboardImageLimitsRejectInvalidAndOversizedPayloads() {
        XCTAssertFalse(ClipboardPolicy.acceptsImage(Data()))
        XCTAssertFalse(ClipboardPolicy.acceptsImage(Data(repeating: 0, count: ClipboardPolicy.maxImageBytes + 1)))
        XCTAssertTrue(ClipboardPolicy.acceptsImage(makePNG(width: 2, height: 2)))
    }

    func testAtomicJSONStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurtyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("test.json")
        let store = AtomicJSONStore<[String]>(url: url)
        try store.save(["локально", "безопасно"])
        XCTAssertEqual(store.load(default: []), ["локально", "безопасно"])

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testMediaWireFormatRoundTripAndCommandAllowlist() throws {
        let original = MediaSnapshot(
            source: "Music",
            title: "Track",
            artist: "Artist",
            album: "Album",
            isPlaying: true,
            duration: 120,
            position: 15
        )
        XCTAssertEqual(try MediaWireFormat.decode(MediaWireFormat.encode(original)), original)
        XCTAssertNil(MediaCommand(rawValue: "run arbitrary script"))
        XCTAssertEqual(Set(MediaCommand.allCases.map(\.rawValue)), ["togglePlayPause", "next", "previous"])
    }

    @MainActor
    func testClipboardAndMediaAreEnabledByDefault() {
        let suiteName = "dev.curty.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = Preferences(defaults: defaults)

        XCTAssertTrue(preferences.clipboardMonitoringEnabled)
        XCTAssertTrue(preferences.mediaIntegrationEnabled)
        XCTAssertFalse(preferences.clipboardImagesEnabled)
    }

    func testTranslationLanguageDetection() {
        XCTAssertEqual(TranslationLanguageDetector.direction(for: "Hello, how are you?"), .englishToRussian)
        XCTAssertEqual(TranslationLanguageDetector.direction(for: "Привет, как дела?"), .russianToEnglish)
        XCTAssertEqual(TranslationLanguageDetector.direction(for: "hello привет hello"), .englishToRussian)
        XCTAssertNil(TranslationLanguageDetector.direction(for: "12345 — !"))
    }

    func testPanelActivationZoneAndCloseTiming() {
        let frame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let fallback = PanelInteractionPolicy.activationRect(
            screenFrame: frame,
            safeAreaTop: 0,
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )
        XCTAssertTrue(fallback.contains(NSPoint(x: frame.midX, y: frame.maxY - 20)))
        XCTAssertGreaterThanOrEqual(fallback.height, 34)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.sampleInterval, 1.0 / 60.0)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.closeDelay, 0.225)
        XCTAssertGreaterThan(PanelInteractionPolicy.idleSampleInterval, PanelInteractionPolicy.sampleInterval)
        XCTAssertLessThanOrEqual(PanelInteractionPolicy.idleSampleInterval, 0.15)

        let notch = PanelInteractionPolicy.activationRect(
            screenFrame: frame,
            safeAreaTop: 38,
            leftAuxiliaryArea: NSRect(x: 0, y: 862, width: 620, height: 38),
            rightAuxiliaryArea: NSRect(x: 820, y: 862, width: 620, height: 38)
        )
        XCTAssertTrue(notch.contains(NSPoint(x: 720, y: 880)))
        XCTAssertGreaterThan(notch.width, 200)

        // The cursor reaches exactly frame.maxY when shoved into the top edge.
        XCTAssertTrue(fallback.contains(NSPoint(x: frame.midX, y: frame.maxY)))
        XCTAssertTrue(notch.contains(NSPoint(x: 720, y: frame.maxY)))
    }

    func testSeekValueIsClampedAndRenderedAsBareDigits() {
        XCTAssertEqual(MediaSeekPolicy.clamp(-5, duration: 200), 0)
        XCTAssertEqual(MediaSeekPolicy.clamp(500, duration: 200), 200)
        XCTAssertEqual(MediaSeekPolicy.clamp(42, duration: 200), 42)
        XCTAssertEqual(MediaSeekPolicy.clamp(.nan, duration: 200), 0)
        XCTAssertEqual(MediaSeekPolicy.clamp(42, duration: 0), 0)

        // A comma or any non-numeric character here would land inside the script.
        let rendered = MediaSeekPolicy.format(163.983993)
        XCTAssertEqual(rendered, "163.984")
        XCTAssertTrue(rendered.allSatisfy { $0.isNumber || $0 == "." })
        XCTAssertEqual(MediaSeekPolicy.format(.infinity), "0.000")
        XCTAssertEqual(MediaSeekPolicy.format(-1), "0.000")
    }

    @MainActor
    func testSettingsIsATabRatherThanASeparateWindow() {
        // Settings must stay reachable as a panel tab, but out of the tool list.
        XCTAssertTrue(AppModel.Tool.allCases.contains(.settings))
        XCTAssertFalse(AppModel.Tool.primary.contains(.settings))
        XCTAssertEqual(AppModel.Tool.primary.count, AppModel.Tool.allCases.count - 1)
        XCTAssertFalse(AppModel.Tool.settings.symbol.isEmpty)
        XCTAssertFalse(AppModel.Tool.settings.title.isEmpty)
    }

    @MainActor
    func testToolOrderSurvivesStaleAndBrokenStoredValues() {
        let available = AppModel.Tool.primary

        XCTAssertEqual(ToolOrderPolicy.resolve(stored: [], available: available), available)

        // Unknown names, duplicates and a tool that is not on the rail are dropped,
        // and anything the stored order omits still shows up at the end.
        let messy = ["clipboard", "clipboard", "нет-такого", "settings", "media"]
        let resolved = ToolOrderPolicy.resolve(stored: messy, available: available)
        XCTAssertEqual(resolved.prefix(2).map(\.rawValue), ["clipboard", "media"])
        XCTAssertEqual(Set(resolved), Set(available))
        XCTAssertEqual(resolved.count, available.count)

        let toFront = ToolOrderPolicy.move(.notes, toIndex: 0, in: available)
        XCTAssertEqual(toFront.first, .notes)
        XCTAssertEqual(Set(toFront), Set(available))
        XCTAssertEqual(toFront.count, available.count)

        // Dragging past either end parks the icon at the end, never drops it.
        let toBack = ToolOrderPolicy.move(.media, toIndex: 99, in: available)
        XCTAssertEqual(toBack.last, .media)
        XCTAssertEqual(toBack.count, available.count)
        let clampedLow = ToolOrderPolicy.move(.notes, toIndex: -5, in: available)
        XCTAssertEqual(clampedLow.first, .notes)
        XCTAssertEqual(ToolOrderPolicy.move(.media, toIndex: 0, in: available), available)
    }

    func testCalendarHorizonSpansDayAndWeek() {
        XCTAssertEqual(CalendarStore.Horizon.day.duration, 24 * 60 * 60)
        XCTAssertEqual(CalendarStore.Horizon.week.duration, 7 * 24 * 60 * 60)
        XCTAssertGreaterThan(CalendarStore.Horizon.week.limit, CalendarStore.Horizon.day.limit)
        XCTAssertEqual(Set(CalendarStore.Horizon.allCases.map(\.title)), ["Сутки", "Неделя"])
    }

    func testSystemOverlayNeedsAScreenCoveringWindowAboveNormalWindows() {
        let screen = CGSize(width: 1_512, height: 982)

        // Mission Control draws at these layers.
        XCTAssertTrue(SystemOverlayPolicy.isOverlayWindow(layer: 20, width: 1_512, height: 982, screenSize: screen))
        XCTAssertTrue(SystemOverlayPolicy.isOverlayWindow(layer: 18, width: 1_512, height: 982, screenSize: screen))

        // The Dock's wallpaper is full screen too, but sits at desktop level:
        // counting it made a bare desktop look like Mission Control.
        XCTAssertFalse(SystemOverlayPolicy.isOverlayWindow(layer: -2_147_483_622, width: 1_512, height: 982, screenSize: screen))
        XCTAssertFalse(SystemOverlayPolicy.isOverlayWindow(layer: 0, width: 1_512, height: 982, screenSize: screen))

        // The Dock strip itself is above normal windows but nowhere near full screen.
        XCTAssertFalse(SystemOverlayPolicy.isOverlayWindow(layer: 20, width: 1_512, height: 90, screenSize: screen))
        XCTAssertFalse(SystemOverlayPolicy.isOverlayWindow(layer: 20, width: 120, height: 982, screenSize: screen))
        XCTAssertFalse(SystemOverlayPolicy.isOverlayWindow(layer: 20, width: 1_512, height: 982, screenSize: .zero))
    }

    func testLaunchAtLoginRecognizesSupportedApplicationFolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertTrue(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Applications/Curty.app"),
            homeDirectory: home
        ))
        XCTAssertTrue(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Applications/Curty.app"),
            homeDirectory: home
        ))
        XCTAssertFalse(LaunchAtLoginPolicy.isInApplicationsFolder(
            bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/Curty.app"),
            homeDirectory: home
        ))
    }

    func testLaunchAtLoginErrorIsFriendlyAndLocalized() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 22)
        let message = LaunchAtLoginPolicy.friendlyMessage(
            for: error,
            bundleURL: URL(fileURLWithPath: "/tmp/Curty.app")
        )
        XCTAssertTrue(message.contains("Программы"))
        XCTAssertFalse(message.contains("Invalid argument"))
    }

    private func makePNG(width: Int, height: Int) -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return representation.representation(using: .png, properties: [:])!
    }
}
