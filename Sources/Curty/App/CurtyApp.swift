import SwiftUI

@main
struct CurtyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // A SwiftUI App needs a scene, but Curty never opens one: it is a menu bar
    // agent whose whole interface is the panel, and settings now live there too.
    var body: some Scene {
        Settings {
            SettingsPane(model: appDelegate.model)
                .padding(18)
                .frame(width: 460, height: 420)
        }
    }
}
