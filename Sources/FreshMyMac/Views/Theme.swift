import AppKit
import SwiftUI

/// PhoneDrop ile ortak "Warm Modern Utility" tasarım sistemi: sıcak kâğıt tonları üzerinde güneş sarısı.
/// Renkler sistem görünümüne ve uygulamadaki tema seçimine göre açık/koyu değişir.
enum Theme {
    static func ns(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    private static func color(_ light: Int, _ dark: Int) -> Color { Color(nsColor: ns(light, dark)) }

    /// Kenar çubuğu ve pencere zemini.
    static let bg = color(0xFFFBF0, 0x1F1D18)
    /// İçerik alanı zemini (kenar çubuğundan bir ton farklı).
    static let content = color(0xFDF9F5, 0x1F1D18)
    static let card = color(0xFFFFFF, 0x2A2720)
    static let fg = color(0x2B2A28, 0xF5F0E1)
    static let mute = color(0x8A857A, 0x9E988A)
    static let line = color(0xEFEAE0, 0x38342B)
    /// Marka sarısı: yalnızca dolgu. Üzerindeki metin `onAcc` rengindedir.
    static let acc = color(0xFFD230, 0xFFD230)
    static let onAcc = color(0x2B2A28, 0x2B2A28)
    static let tint = color(0xFFF4C7, 0x38342B)
    /// Sarı, kâğıt üzerinde metin olarak okunmaz; bağlantılar orada koyu tonunu kullanır.
    static let link = color(0x735C00, 0xFFD230)
    static let okSoft = color(0xCDEFE0, 0x24402F)
    static let onOk = color(0x1F6B4A, 0x7CCFA8)
    static let warnSoft = color(0xFFE1DC, 0x45291F)
    static let onWarn = color(0xA3402F, 0xF2877B)

    // Pastel aksanlar: kategori ve dosya türü plakaları (iki temada da aynı, üzerinde koyu metin).
    static let sky = color(0xCFE6F7, 0xCFE6F7)
    static let lavender = color(0xE1DAF7, 0xE1DAF7)
    static let peach = color(0xFFD9C7, 0xFFD9C7)
    static let mint = color(0xCDEFE0, 0xCDEFE0)
    static let rose = color(0xF9D5DF, 0xF9D5DF)

    /// Dosya adından, türüne göre pastel renk.
    static func typeColor(_ name: String) -> Color {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "dng", "raw", "bmp", "svg", "psd", "tiff": sky
        case "mp4", "mov", "mkv", "avi", "webm", "3gp", "m4v": rose
        case "mp3", "wav", "m4a", "flac", "ogg", "aac", "opus": peach
        case "zip", "rar", "7z", "tar", "gz", "apk", "dmg", "iso", "pkg", "xip": lavender
        default: mint
        }
    }

    /// Sayılar için eşit genişlikli rakamlar.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension TaskCategory {
    var plate: Color {
        switch self {
        case .system: Theme.sky
        case .privacy: Theme.lavender
        case .performance: Theme.peach
        case .developer: Theme.mint
        }
    }
}

// MARK: - Tema seçimi

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("Sistem", "System")
        case .light: L("Açık", "Light")
        case .dark: L("Koyu", "Dark")
        }
    }

    /// `preferredColorScheme(nil)` macOS'ta sisteme geri dönmüyor; görünüm uygulama genelinde ayarlanır.
    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func applyStored() {
        (AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system).apply()
    }
}

// MARK: - Bileşenler

/// Hap biçimli buton: ekrandaki tek ana eylem için sarı, diğerleri için yumuşak ton.
struct PillButton: ButtonStyle {
    var primary = false
    var large = false
    /// Bulunduğu genişliği doldurur (menü çubuğu penceresindeki düğmeler).
    var fill = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(primary && enabled ? Theme.onAcc : (enabled ? Theme.fg : Theme.mute))
            .lineLimit(1).fixedSize()
            .frame(maxWidth: fill ? .infinity : nil)
            .padding(.horizontal, large ? 16 : 12).padding(.vertical, large ? 8 : 6)
            // Pasif ana düğme saydam sarı yerine nötr tonla çizilir (koyu temada zeytin rengine dönmesin).
            .background(primary && enabled ? Theme.acc : Theme.tint, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButton {
    static var pill: PillButton { PillButton() }
    static var pillPrimary: PillButton { PillButton(primary: true) }
}

/// Seçili olunca sarı dolgulu yuvarlatılmış kare onay kutusu; kısmi seçimde çizgi gösterir.
struct CheckStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                let on = configuration.isOn || configuration.isMixed
                RoundedRectangle(cornerRadius: 5)
                    .fill(on ? Theme.acc : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Color.clear : Theme.mute.opacity(0.6), lineWidth: 1.5))
                    .overlay {
                        if on {
                            Image(systemName: configuration.isMixed ? "minus" : "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Theme.onAcc)
                        }
                    }
                    .frame(width: 18, height: 18)
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.fg)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
    }
}

extension ToggleStyle where Self == CheckStyle {
    static var check: CheckStyle { CheckStyle() }
}

/// Açıkken sarı izli anahtar.
struct SwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Capsule()
                .fill(configuration.isOn ? Theme.acc : Theme.line)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 1, y: 1).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

extension ToggleStyle where Self == SwitchStyle {
    static var yellowSwitch: SwitchStyle { SwitchStyle() }
}

/// Pastel zeminli küçük yuvarlak kare: içinde ikon ya da kısa etiket.
struct Plate<Content: View>: View {
    var color: Color
    var size: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Theme.onAcc)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.29))
    }
}

extension Plate where Content == AnyView {
    init(icon: String, color: Color, size: CGFloat = 28) {
        self.init(color: color, size: size) {
            AnyView(Image(systemName: icon).font(.system(size: size * 0.46, weight: .medium)))
        }
    }

    /// Dosya uzantısını gösteren plaka.
    init(fileName: String, size: CGFloat = 28) {
        self.init(color: Theme.typeColor(fileName), size: size) {
            AnyView(Text(verbatim: String((fileName as NSString).pathExtension.uppercased().prefix(4)))
                .font(.system(size: 8, weight: .bold, design: .rounded)))
        }
    }
}

/// BÜYÜK HARFLİ, harf aralıklı bölüm başlığı.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased(with: L10n.locale))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.9)
            .foregroundStyle(Theme.mute)
    }
}

/// Küçük kapsül etiket (ör. "Hazır", "5 öğe").
struct Chip: View {
    let text: String
    var background = Theme.tint
    var foreground = Theme.link

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

extension View {
    /// İnce kenarlıklı, beyaz (ya da koyu kahve) yuvarlak köşeli kart.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
    }
}

/// Kart içindeki satırlar arasında, ikon hizasından başlayan ayırıcı.
struct RowDivider: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, leading)
    }
}
