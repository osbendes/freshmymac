import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// Masaüstü widget'ı. Sandbox içinde çalışır; temizliği kendisi yapmaz. Düğmeler `WidgetCleanIntent`
// ile isteği uygulamaya öne getirmeden iletir; uygulama ilerleyişi `WidgetPhase` dosyasına yazar ve
// widget "temizleniyor" animasyonunu ve sonucu ondan çizer. Büyük boydaki seçim kutuları ortak ön ayar
// dosyasını (PresetStore) doğrudan günceller; küçük/orta boy, sağ tık › "Widget'ı Düzenle" ile kendi
// görevlerini seçebilir.

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

/// Widget düğmesi: temizlik isteğini uygulamaya iletir. Uygulama kapalıysa arka planda (penceresiz) başlar,
/// açıksa öne gelmeden işler.
struct WidgetCleanIntent: AppIntent {
    static let title: LocalizedStringResource = "Run cleanup"
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: String

    /// Virgülle ayrılmış görevler; boşsa uygulamadaki Tek Tık ön ayarı.
    @Parameter(title: "Tasks")
    var taskList: String

    init() {}
    init(_ action: WidgetRequest.Action, taskIDs: [String]? = nil) {
        self.action = action.rawValue
        self.taskList = taskIDs?.joined(separator: ",") ?? ""
    }

    func perform() async throws -> some IntentResult {
        let request = WidgetRequest(
            action: WidgetRequest.Action(rawValue: action) ?? .clean,
            taskIDs: taskList.isEmpty ? nil : taskList.split(separator: ",").map(String.init)
        )
        // Widget hemen "temizleniyor" görünümüne geçsin; ilerleyişi bundan sonra uygulama yazar.
        WidgetPhase(kind: .requested).save()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            try await NSWorkspace.shared.open(request.url, configuration: configuration)
        } catch {
            syncLanguage(WidgetStatus.load())
            WidgetPhase(kind: .failed, message: L("FreshMyMac açılamadı.", "Couldn't open FreshMyMac.")).save()
        }
        return .result()
    }
}

// MARK: - Yapılandırma (sağ tık › Widget'ı Düzenle)

struct CleanTaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cleanup Task"
    static let defaultQuery = CleanTaskQuery()

    let id: String
    let title: String
    let icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: icon))
    }
}

/// Görev listesi uygulamanın yazdığı durum dosyasından gelir (adlar uygulamanın dilinde).
struct CleanTaskQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CleanTaskEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CleanTaskEntity] { Self.all() }

    static func all() -> [CleanTaskEntity] {
        (WidgetStatus.load()?.tasks ?? []).map { CleanTaskEntity(id: $0.id, title: $0.title, icon: $0.icon) }
    }
}

struct CleanConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "One-Click Clean"
    static let description = IntentDescription("Choose which cleanups this widget runs. Leave empty to use the One-Click preset from the app.")

    @Parameter(title: "Tasks")
    var tasks: [CleanTaskEntity]?

    init() {}
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
    /// Bu widget'a özel görevler (yapılandırmadan); `nil` ise ön ayar.
    var custom: [String]?
    /// Bu girişte gösterilecek temizlik aşaması (sürüyor ya da sonuç); `nil` ise olağan görünüm.
    var phase: WidgetPhase?

    var activeIDs: Set<String> { custom.map(Set.init) ?? preset }
    var presetBytes: Int64 { status.presetBytes(activeIDs) }
    var selectedCount: Int { status.tasks.filter { activeIDs.contains($0.id) }.count }
    var needsPassword: Bool { status.tasks.contains { $0.needsPassword && activeIDs.contains($0.id) } }

    static func current(custom: [String]? = nil) -> StatusEntry {
        let status = WidgetStatus.load() ?? WidgetStatus()
        syncLanguage(status)
        return StatusEntry(date: .now, status: status, preset: PresetStore.load() ?? PresetStore.defaultIDs, custom: custom)
    }

    static var placeholder: StatusEntry {
        syncLanguage(WidgetStatus.load())
        return StatusEntry(
            date: .now,
            status: WidgetStatus(tasks: [
                .init(id: "user-caches", title: L("Uygulama Önbelleği", "App Cache"), icon: "archivebox", bytes: 2_400_000_000, needsPassword: false),
                .init(id: "user-logs", title: L("Günlükler", "Logs"), icon: "doc.text", bytes: 300_000_000, needsPassword: false),
                .init(id: "browser-caches", title: L("Tarayıcı Önbelleği", "Browser Cache"), icon: "globe", bytes: 900_000_000, needsPassword: false),
                .init(id: "dns-flush", title: L("İnternet Önbelleği", "Internet Cache"), icon: "network", bytes: nil, needsPassword: false),
            ]),
            preset: PresetStore.defaultIDs
        )
    }

    /// Sürüyorsa aşamayı gösterip kısa süre sonra yeniden sorar; sonuç varsa gösterip süresi bitince
    /// olağan görünüme döner. Uygulama her aşama değişiminde ayrıca yeniletir.
    static func timeline(custom: [String]?) -> Timeline<StatusEntry> {
        var base = current(custom: custom)
        let normalRefresh = Date.now.addingTimeInterval(30 * 60)
        guard let phase = WidgetPhase.load() else { return Timeline(entries: [base], policy: .after(normalRefresh)) }
        if phase.isRunning {
            base.phase = phase
            return Timeline(entries: [base], policy: .after(.now.addingTimeInterval(15)))
        }
        if phase.isShowingResult {
            var result = base
            result.phase = phase
            let after = StatusEntry(date: phase.resultEnds, status: base.status, preset: base.preset, custom: custom)
            return Timeline(entries: [result, after], policy: .after(normalRefresh))
        }
        return Timeline(entries: [base], policy: .after(normalRefresh))
    }
}

/// Küçük/orta boy: sağ tıktaki yapılandırmayla.
struct ConfigurableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .placeholder }

    func snapshot(for configuration: CleanConfigIntent, in context: Context) async -> StatusEntry {
        let entry = StatusEntry.current(custom: configuration.customIDs)
        return entry.status.tasks.isEmpty ? .placeholder : entry
    }

    func timeline(for configuration: CleanConfigIntent, in context: Context) async -> Timeline<StatusEntry> {
        StatusEntry.timeline(custom: configuration.customIDs)
    }
}

/// Büyük boy: seçimi widget'ın üzerindeki kutularla yapılır, yapılandırması yok.
struct PickerProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let entry = StatusEntry.current()
        completion(entry.status.tasks.isEmpty ? .placeholder : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(StatusEntry.timeline(custom: nil))
    }
}

private extension CleanConfigIntent {
    var customIDs: [String]? {
        guard let tasks, !tasks.isEmpty else { return nil }
        return tasks.map(\.id)
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
    var okSoft: Color { hex(dark ? 0x24402F : 0xCDEFE0) }
    var onOk: Color { hex(dark ? 0x7CCFA8 : 0x1F6B4A) }
    var warnSoft: Color { hex(dark ? 0x45291F : 0xFFE1DC) }
    var onWarn: Color { hex(dark ? 0xF2877B : 0xA3402F) }

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

/// Aşamaya göre büyük düğmenin içi: ✨ Temizle → dönen halka → ✓ sonuç.
private struct PhaseTile: View {
    @Environment(\.colorScheme) private var scheme
    let phase: WidgetPhase?
    var iconSize: CGFloat = 36

    var body: some View {
        let p = Palette(scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(fill(p))
            Group {
                switch phase?.kind {
                case .requested?, .cleaning?:
                    VStack(spacing: 8) {
                        // Zamanlayıcıya bağlı ilerleme halkası widget'ta kendiliğinden döner.
                        ProgressView(timerInterval: phase!.date...phase!.date.addingTimeInterval(12), countsDown: false) { EmptyView() }
                            .progressViewStyle(.circular)
                            .tint(p.onAcc)
                            .frame(width: iconSize + 6, height: iconSize + 6)
                        Text(L("Temizleniyor…", "Cleaning…")).font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(p.onAcc)
                case .done?:
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: iconSize, weight: .semibold))
                        if let freed = phase?.freedBytes {
                            Text(bytes(freed))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                        } else {
                            Text(L("Tamam", "Done")).font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(p.onOk)
                case .failed?:
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: iconSize - 6, weight: .semibold))
                        Text(L("Tekrar dene", "Try again")).font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(p.onWarn)
                case nil:
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: iconSize, weight: .semibold))
                        Text(L("Temizle", "Clean")).font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(p.onAcc)
                }
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .id(phase?.kind)
        }
    }

    private func fill(_ p: Palette) -> Color {
        switch phase?.kind {
        case .done?: p.okSoft
        case .failed?: p.warnSoft
        default: p.acc
        }
    }
}

/// Aşamaya göre alttaki kısa not.
private func phaseCaption(_ entry: StatusEntry) -> String {
    guard let phase = entry.phase else {
        return entry.presetBytes > 0
            ? L("≈ \(bytes(entry.presetBytes)) kazanç", "≈ \(bytes(entry.presetBytes)) to free")
            : L("\(entry.selectedCount) görev hazır", "\(entry.selectedCount) tasks ready")
    }
    switch phase.kind {
    case .requested, .cleaning: return L("Arka planda temizleniyor", "Cleaning in the background")
    case .done: return phase.freedBytes.map { L("\(bytes($0)) boşaltıldı", "\(bytes($0)) freed") } ?? (phase.message ?? L("Tamamlandı", "Done"))
    case .failed: return phase.message ?? L("Temizlik başarısız", "Cleanup failed")
    }
}

/// Sade: tek büyük düğme, altında küçük kazanç notu. Uygulama penceresi açılmaz.
private struct SmallView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 8) {
            Button(intent: WidgetCleanIntent(.clean, taskIDs: entry.custom)) {
                PhaseTile(phase: entry.phase)
            }
            .buttonStyle(.plain)
            .disabled(entry.phase?.isRunning == true)
            Text(phaseCaption(entry))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(p.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
    }
}

private struct MediumView: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    var body: some View {
        let p = Palette(scheme)
        HStack(alignment: .top, spacing: 14) {
            Button(intent: WidgetCleanIntent(.clean, taskIDs: entry.custom)) {
                PhaseTile(phase: entry.phase, iconSize: 30)
            }
            .buttonStyle(.plain)
            .disabled(entry.phase?.isRunning == true)
            .frame(width: 130)

            VStack(alignment: .leading, spacing: 4) {
                Header()
                Spacer(minLength: 0)
                Text(entry.phase?.freedBytes.map(bytes) ?? bytes(entry.presetBytes))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(p.fg)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(entry.phase?.kind == .done ? L("boşaltıldı", "freed") : L("temizlenebilir", "cleanable"))
                    .font(.system(size: 11)).foregroundStyle(p.mute)
                Spacer(minLength: 0)
                Text(entry.phase == nil
                     ? L("\(entry.selectedCount) görev · sağ tık › Widget'ı Düzenle", "\(entry.selectedCount) tasks · right-click › Edit Widget")
                     : phaseCaption(entry))
                    .font(.system(size: 10)).foregroundStyle(p.mute)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Button(intent: WidgetCleanIntent(.flushdns)) {
                    Pill(title: L("İnternet Önbelleği", "Internet Cache"), systemImage: "network", primary: false)
                }
                .buttonStyle(.plain)
                .disabled(entry.phase?.isRunning == true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

            Button(intent: WidgetCleanIntent(.clean)) {
                LargeCleanButton(entry: entry)
            }
            .buttonStyle(.plain)
            .disabled(entry.selectedCount == 0 || entry.phase?.isRunning == true)

            HStack {
                LastClean(status: entry.status)
                Spacer()
                if entry.needsPassword {
                    Label(L("Şifre istenebilir", "May ask for password"), systemImage: "lock.fill")
                        .font(.system(size: 10)).foregroundStyle(p.mute)
                }
            }
        }
    }
}

/// Büyük boydaki geniş düğme; aşamaya göre "Temizleniyor…" ya da "✓ X boşaltıldı" olur.
private struct LargeCleanButton: View {
    @Environment(\.colorScheme) private var scheme
    let entry: StatusEntry

    var body: some View {
        let p = Palette(scheme)
        HStack(spacing: 8) {
            switch entry.phase?.kind {
            case .requested?, .cleaning?:
                ProgressView(timerInterval: entry.phase!.date...entry.phase!.date.addingTimeInterval(12), countsDown: false) { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(p.onAcc)
                    .frame(width: 16, height: 16)
                Text(L("Temizleniyor…", "Cleaning…"))
            case .done?:
                Image(systemName: "checkmark.circle.fill")
                Text(phaseCaption(entry)).contentTransition(.numericText())
            case .failed?:
                Image(systemName: "exclamationmark.triangle.fill")
                Text(phaseCaption(entry))
            case nil:
                Image(systemName: "sparkles")
                Text(entry.presetBytes > 0
                     ? L("Seçilenleri Temizle · \(bytes(entry.presetBytes))", "Clean Selected · \(bytes(entry.presetBytes))")
                     : L("Seçilenleri Temizle", "Clean Selected"))
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(background(p), in: Capsule())
        .foregroundStyle(foreground(p))
        .transition(.opacity)
        .id(entry.phase?.kind)
    }

    private func background(_ p: Palette) -> Color {
        switch entry.phase?.kind {
        case .done?: p.okSoft
        case .failed?: p.warnSoft
        default: p.acc
        }
    }

    private func foreground(_ p: Palette) -> Color {
        switch entry.phase?.kind {
        case .done?: p.onOk
        case .failed?: p.onWarn
        default: p.onAcc
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

/// Küçük ve orta boy: tek tıkla temizlik; sağ tık › "Widget'ı Düzenle" ile görevleri seçilebilir.
struct QuickCleanWidget: Widget {
    var body: some WidgetConfiguration {
        syncLanguage(WidgetStatus.load())
        return AppIntentConfiguration(kind: "QuickClean", intent: CleanConfigIntent.self, provider: ConfigurableProvider()) { entry in
            QuickCleanWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(L("Tek Tık Temizlik", "One-Click Clean"))
        .description(L("Tek tıkla temizler; uygulama penceresi açılmaz. Görevleri seçmek için widget'a sağ tıklayıp Widget'ı Düzenle'yi seçin.",
                       "Cleans with one click without opening the app window. Right-click the widget › Edit Widget to choose tasks."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Büyük boy: görevler widget'ın üzerindeki kutularla seçilir (uygulamadaki Tek Tık ön ayarı).
struct TaskPickerWidget: Widget {
    var body: some WidgetConfiguration {
        syncLanguage(WidgetStatus.load())
        return StaticConfiguration(kind: "QuickCleanPicker", provider: PickerProvider()) { entry in
            QuickCleanWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(L("Tek Tık Temizlik · Görevler", "One-Click Clean · Tasks"))
        .description(L("Temizlenecek görevleri doğrudan masaüstünden seçin ve tek tıkla temizleyin.",
                       "Pick the tasks right on the desktop and clean them with one click."))
        .supportedFamilies([.systemLarge])
    }
}

@main
struct FreshMyMacWidgets: WidgetBundle {
    var body: some Widget {
        QuickCleanWidget()
        TaskPickerWidget()
    }
}
