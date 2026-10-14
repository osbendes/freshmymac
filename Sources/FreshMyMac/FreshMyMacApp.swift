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
                .background(LaunchWindowGate())
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
        // Arka planda başlatıldıysa ya da widget isteği sürüyorsa kapanma; istek bitince AppState kapatır.
        if AppState.shared.backgroundSession || AppState.shared.pendingWidgetRequests > 0 { return false }
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

/// SwiftUI `Window` sahnesi açılışta pencereyi her zaman oluşturur; widget'ın arka plan isteğini taşıyan
/// URL olayı ise ancak pencere oluştuktan sonra gelir. Bu yüzden açılış penceresi kısa bir süre saydam
/// tutulur: bu sürede arka plan isteği gelirse pencere hiç görünmeden kapanır, gelmezse belirir.
/// Uygulama menü çubuğunda çalışmaya devam eder; Dock'tan ya da menüden pencere yeniden açılabilir.
private struct LaunchWindowGate: NSViewRepresentable {
    static let delay: Duration = .milliseconds(600)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard AppState.shared.launchGatePending, let window = view.window else { return }
            AppState.shared.launchGatePending = false
            window.alphaValue = 0
            try? await Task.sleep(for: Self.delay)
            if AppState.shared.backgroundSession {
                window.close()
            }
            window.alphaValue = 1
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
