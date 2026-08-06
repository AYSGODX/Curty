import SwiftUI

@main
struct CurtyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
                .frame(width: 520, height: 420)
        }
    }
}
