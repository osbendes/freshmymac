import AppIntents
import SwiftUI
import WidgetKit

// Masaüstü widget'ı. Sandbox içinde çalışır; temizliği kendisi yapmaz,
// `freshmymac://` adresleriyle ana uygulamaya iletir. Büyük boydaki seçim kutuları
// ise ortak ön ayar dosyasını (PresetStore) doğrudan günceller.

// MARK: - Etkileşim

struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle cleanup task"
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        PresetStore.toggle(taskID)
        return .result()
    }
}

/// Widget, uygulamanın seçtiği dilde görünür (durum dosyasındaki `language`).
private func syncLanguage(_ status: WidgetStatus?) {
    L10n.language = status?.language ?? .system
}

// MARK: - Zaman çizelgesi

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus
    let preset: Set<String>

    var presetBytes: Int64 { status.presetBytes(preset) }
    var selectedCount: Int { status.tasks.filter { preset.contains($0.id) }.count }

    static func current() -> StatusEntry {
        let status = WidgetStatus.load() ?? WidgetStatus()
        syncLanguage(status)
        return StatusEntry(date: .now, status: status, preset: PresetStore.load() ?? PresetStore.defaultIDs)
    }

    static var placeholder: StatusEntry {
        syncLanguage(WidgetStatus.load())
        return StatusEntry(
            date: .now,
            status: WidgetStatus(tasks: [
                .init(id: "user-caches", title: L("Uygulama Önbelleği", "App Cache"), icon: "archivebox", bytes: 2_400_000_000, needsPassword: false),
                .init(id: "user-logs", title: L("Günlükler", "Logs"), icon: "doc.text", bytes: 300_000_000, needsPassword: false),
                .init(id: "browser-caches", title: L("Tarayıcı Önbelleği", "Browser Cache"), icon: "globe", bytes: 900_000_000, needsPassword: false),
                .init(id: "dns-flush", title: L("İnternet Önbelleği", "Internet Cache"), icon: "network", bytes: nil, needsPassword: true),
            ]),
            preset: PresetStore.defaultIDs
        )
    }
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let entry = StatusEntry.current()
        completion(entry.status.tasks.isEmpty ? .placeholder : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        // Uygulama durum değiştikçe yeniletir; bu yalnızca yedek yenileme.
        completion(Timeline(entries: [.current()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Renkler

/// Uygulamadaki `Theme` ile aynı "Warm Modern Utility" paleti. Widget ayrı süreçte çizildiği için
/// dinamik NSColor yerine renk şemasına göre seçilir.
private struct Palette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var bg: Color { hex(dark ? 0x1F1D18 : 0xFFFBF0) }
    var card: Color { hex(dark ? 0x2A2720 : 0xFFFFFF) }
    var fg: Color { hex(dark ? 0xF5F0E1 : 0x2B2A28) }
    var mute: Color { hex(dark ? 0x9E988A : 0x8A857A) }
    var line: Color { hex(dark ? 0x38342B : 0xEFEAE0) }
    var tint: Color { hex(dark ? 0x38342B : 0xFFF4C7) }
    var acc: Color { hex(0xFFD230) }
    var onAcc: Color { hex(0x2B2A28) }

    private func hex(_ value: Int) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

// MARK: - Görünümler

struct QuickCleanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            default: MediumView(entry: entry)
            }
        }
        .fontDesign(.rounded)
        .environment(\.locale, L10n.locale)
    }
}

private struct WidgetBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Palette(scheme).bg }
}

/// Sade: tek büyük düğme, altında küçük kazanç notu. Widget'ın tamamı tıklanabilir.
private struct SmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(p.acc)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 36, weight: .semibold))
                        Text(L("Temizle", "Clean")).font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(p.onAcc)
                }
            Text(entry.presetBytes > 0
                 ? L("≈ \(bytes(entry.presetBytes)) kazanç", "≈ \(bytes(entry.presetBytes)) to free")
                 : L("\(entry.selectedCount) görev hazır", "\(entry.selectedCount) tasks ready"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .widgetURL(WidgetStatus.cleanURL)
    }
}

private struct MediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    var body: some View {
        let p = Palette(scheme)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Header()
                Spacer(minLength: 0)
                Text(bytes(entry.presetBytes))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.fg)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(L("temizlenebilir", "cleanable")).font(.system(size: 11)).foregroundStyle(p.mute)
                Spacer(minLength: 0)
                LastClean(status: entry.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Link(destination: WidgetStatus.cleanURL) {
                    Pill(title: L("Tek Tık Temizle", "One-Click Clean"), systemImage: "sparkles", primary: true)
                }
                Link(destination: WidgetStatus.flushDNSURL) {
                    Pill(title: L("İnternet Önbelleği", "Internet Cache"), systemImage: "network", primary: false)
                }
                Text(L("\(entry.selectedCount) görev seçili", "\(entry.selectedCount) tasks selected"))
                    .font(.system(size: 10)).foregroundStyle(p.mute)
                Spacer(minLength: 0)
            }
            .frame(width: 150)
        }
    }
}

/// Seçim kutularıyla ön ayarı düzenleyip seçilenleri temizler.
private struct LargeView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Header()
                Spacer()
                Text("\(entry.selectedCount) / \(entry.status.tasks.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(p.fg)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(p.tint, in: Capsule())
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(entry.status.tasks) { task in
                    TaskToggle(task: task, isOn: entry.preset.contains(task.id))
                }
            }
            .padding(12)
            .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.line))

            Spacer(minLength: 0)

            Link(destination: WidgetStatus.cleanURL) {
                Pill(
                    title: entry.presetBytes > 0
                        ? L("Seçilenleri Temizle · \(bytes(entry.presetBytes))", "Clean Selected · \(bytes(entry.presetBytes))")
                        : L("Seçilenleri Temizle", "Clean Selected"),
                    systemImage: "sparkles",
                    primary: true,
                    large: true
                )
            }
            .disabled(entry.selectedCount == 0)

            HStack {
                LastClean(status: entry.status)
                Spacer()
                if entry.status.tasks.contains(where: { $0.needsPassword && entry.preset.contains($0.id) }) {
                    Label(L("Şifre istenebilir", "May ask for password"), systemImage: "lock.fill")
                        .font(.system(size: 10)).foregroundStyle(p.mute)
                }
            }
        }
    }
}

private struct TaskToggle: View {
    @Environment(\.colorScheme) private var scheme
    let task: WidgetStatus.TaskInfo
    let isOn: Bool

    var body: some View {
        let p = Palette(scheme)
        Toggle(isOn: isOn, intent: ToggleTaskIntent(taskID: task.id)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if let size = task.bytes, size > 0 {
                        Text(bytes(size))
                    } else if task.needsPassword {
                        Text(L("şifre ister", "needs password"))
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(p.mute)
            }
        }
        .toggleStyle(CheckToggleStyle(palette: p))
    }
}

/// Uygulamadaki sarı onay kutusunun widget karşılığı. Dokunuşu sistem `intent` ile işler.
private struct CheckToggleStyle: ToggleStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(configuration.isOn ? palette.acc : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(configuration.isOn ? Color.clear : palette.mute.opacity(0.6), lineWidth: 1.5)
                )
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.onAcc)
                    }
                }
                .frame(width: 16, height: 16)
            configuration.label
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct Header: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(p.onAcc)
                .frame(width: 20, height: 20)
                .background(p.acc, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("FreshMyMac")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(p.fg)
        }
    }
}

private struct LastClean: View {
    @Environment(\.colorScheme) private var scheme
    let status: WidgetStatus

    var body: some View {
        let p = Palette(scheme)
        if let date = status.lastCleanDate {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Son temizlik", "Last cleanup")).font(.system(size: 10)).foregroundStyle(p.mute)
                Group {
                    if L10n.isTurkish {
                        Text("\(date, style: .relative) önce · \(bytes(status.lastFreedBytes ?? 0))")
                    } else {
                        Text("\(date, style: .relative) ago · \(bytes(status.lastFreedBytes ?? 0))")
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(p.fg)
            }
        } else {
            Text(L("Henüz temizlik yapılmadı", "No cleanup yet")).font(.system(size: 10)).foregroundStyle(p.mute)
        }
    }
}

private struct Pill: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let systemImage: String
    let primary: Bool
    var large = false

    var body: some View {
        let p = Palette(scheme)
        Label(title, systemImage: systemImage)
            .font(.system(size: large ? 13 : 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, large ? 10 : 8)
            .background(primary ? p.acc : p.tint, in: Capsule())
            .foregroundStyle(primary ? p.onAcc : p.fg)
    }
}

private func bytes(_ value: Int64) -> String {
    value.formatted(.byteCount(style: .file).locale(L10n.locale))
}

// MARK: - Widget

struct QuickCleanWidget: Widget {
    var body: some WidgetConfiguration {
        syncLanguage(WidgetStatus.load())
        return StaticConfiguration(kind: "QuickClean", provider: StatusProvider()) { entry in
            QuickCleanWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(L("Tek Tık Temizlik", "One-Click Clean"))
        .description(L("Seçtiğiniz temizlikleri tek tıkla çalıştırır. Büyük boyda görevleri widget'tan seçebilirsiniz.",
                       "Runs your chosen cleanups with one click. In the large size you can pick tasks right in the widget."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct FreshMyMacWidgets: WidgetBundle {
    var body: some Widget {
        QuickCleanWidget()
    }
}
