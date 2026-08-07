import SwiftUI

@main
struct CurtyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // A SwiftUI App needs a scene, but Curty never opens one: it is a menu bar
    // agent whose whole interface is the panel, and settings now live there too.
    var body: some Scene {
        // Пустая: SwiftUI требует от App хотя бы одну сцену, но настройки живут
        // вкладкой панели. Раньше здесь создавалась вторая SettingsPane — код,
        // который ожил бы при первом изменении activation policy и увёл
        // настройки в отдельное окно на чужом Space.
        Settings { EmptyView() }
    }
}
