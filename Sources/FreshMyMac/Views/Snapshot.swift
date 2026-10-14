import AppKit
import SwiftUI

/// Ekran görüntüsü modu: `-snapshot /yol/dosya.png` ile açılırsa pencereyi PNG olarak kaydedip çıkar.
/// `-screen`, `-appearanceMode`, `-appLanguage`, `-demo YES` ve `-snapshotDelay` (saniye, varsayılan 4) ile
/// birlikte kullanılır. `-snapshotMenu /yol/menu.png` menü çubuğu penceresini de ayrıca kaydeder.
/// Örnek: FreshMyMac -demo YES -screen cleanup -appearanceMode dark -snapshot ~/Desktop/cleanup-dark.png
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshot") else { return }
        let menuPath = defaults.string(forKey: "snapshotMenu")
        let delay = defaults.object(forKey: "snapshotDelay") as? Double ?? 4
        // Demo seçimi kalıcı ayara yazılır; çıkmadan önce kullanıcının kendi seçimi geri konur.
        let savedSelection = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["selectedTasks"]
            ?? defaults.object(forKey: "selectedTasks")
        Task {
            try? await Task.sleep(for: .seconds(delay))
            if Demo.isOn { Demo.apply(to: AppState.shared) }
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.level == .normal }) {
                window.setContentSize(NSSize(width: 1100, height: 760))
                try? await Task.sleep(for: .milliseconds(700))
                // Trafik ışıkları da görünsün diye pencerenin çerçeve görünümü çizilir.
                if let view = window.contentView?.superview ?? window.contentView { write(view, to: path) }
            }
            if let menuPath { await renderMenu(to: menuPath) }
            if Demo.isOn { defaults.set(savedSelection, forKey: "selectedTasks") }
            NSApp.terminate(nil)
        }
    }

    /// Menü çubuğu penceresini ekran dışı bir pencerede çizip kaydeder.
    private static func renderMenu(to path: String) async {
        let host = NSHostingView(rootView: MenuBarView()
            .environment(AppState.shared)
            .tint(Theme.acc)
            .fontDesign(.rounded))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSApp.effectiveAppearance
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        write(host, to: path)
        window.orderOut(nil)
    }

    /// Görünümü, bulunduğu ekrandan bağımsız olarak 2x çözünürlükte PNG'ye yazar.
    private static func write(_ view: NSView, to path: String, scale: CGFloat = 2) {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(filePath: (path as NSString).expandingTildeInPath)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
