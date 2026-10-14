import AppKit
import SwiftUI

@main
struct FreshMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        Window("FreshMyMac", id: "main") {
            ContentView()
                .background(OpenWindowCapture())
                .environment(state)
                .tint(Theme.acc)
                .fontDesign(.rounded)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { state.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("FreshMyMac", systemImage: "sparkles", isInserted: Bindable(state.settings).showMenuBarIcon) {
            MenuBarView()
                .background(OpenWindowCapture())
                .id(state.settings.language)
                .environment(\.locale, L10n.locale)
                .environment(state)
                .tint(Theme.acc)
                .fontDesign(.rounded)
                .onAppear { state.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` ile .app paketi olmadan çalışırken de normal pencere/Dock davranışı için.
        NSApp.setActivationPolicy(.regular)
        AppearanceMode.applyStored()
        Snapshot.runIfRequested()
        if !AppEnvironment.isBundled,
           let icon = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/Resources/AppIcon.icns") {
            NSApp.applicationIconImage = icon
        }
        AppState.shared.start()
    }

    /// Pencere kapatılıp uygulama menü çubuğunda çalışırken Dock simgesine (ya da Finder'dan
    /// uygulamaya) tıklanınca pencereyi geri getirir.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.showMainWindow() }
        return true
    }

    /// Widget'ta seçimler değişmiş olabilir; Ayarlar ekranı güncel kalsın.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.settings.reloadPreset()
    }

    /// Widget düğmeleri `freshmymac://clean` ve `freshmymac://flushdns` adreslerini açar.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { AppState.shared.handle($0) }
    }

    /// Menü çubuğu simgesi açıksa pencere kapansa da uygulama (ve zamanlayıcı) çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppSettings.registerDefaults()
        return !UserDefaults.standard.bool(forKey: AppSettings.Keys.showMenuBarIcon)
    }
}

/// `openWindow` eylemi yalnızca görünümlerin ortamında bulunur; AppDelegate'in de pencereyi
/// açabilmesi için ilk görünen sahneden alınıp `AppState`'e verilir.
private struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear {
            AppState.shared.openMainWindow = { openWindow(id: "main") }
        }
    }
}
