import AppKit
import QuickLookUI

/// Quick Look is driven by AppKit through the responder chain: the shared panel
/// asks the key window whether it will supply preview items. The panel window
/// forwards those questions here.
@MainActor
final class QuickLookCoordinator: NSObject {
    static let shared = QuickLookCoordinator()

    private var previewURL: URL?
    /// Held open for as long as the preview is on screen: Quick Look reads the
    /// file itself, and a shelf file lives outside the container.
    private var scopedURL: URL?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Space toggles, the way it does in Finder.
    func toggle(_ url: URL, isSecurityScoped: Bool) {
        if isVisible, previewURL == url {
            close()
        } else {
            present(url, isSecurityScoped: isSecurityScoped)
        }
    }

    func present(_ url: URL, isSecurityScoped: Bool) {
        releaseScope()
        if isSecurityScoped, url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        previewURL = url

        NSApp.activate(ignoringOtherApps: true)
        let panel = QLPreviewPanel.shared()
        panel?.makeKeyAndOrderFront(nil)
        panel?.reloadData()
    }

    func close() {
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        previewURL = nil
        releaseScope()
    }

    func previewPanelDidClose() {
        previewURL = nil
        releaseScope()
    }

    private func releaseScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}

extension QuickLookCoordinator: @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
}
