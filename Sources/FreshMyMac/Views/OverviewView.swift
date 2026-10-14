import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state
    let navigate: (Screen) -> Void
    /// Son Tek Tık temizliğinde boşaltılan alan; birkaç saniye gösterilir.
    @State private var cleanResult: Int64?

    private struct Slice: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
        /// Halkada çizilen değer. Dolu bir diskte birkaç yüz MB görünmez kalacağı için
        /// temizlenebilir dilime en az ~%1,5'lik bir genişlik verilir; açıklama gerçek değeri gösterir.
        var minimumShare: Double = 0
    }

    /// Başlangıç diskinin adı (ör. "Macintosh HD").
    private static let volumeName = try? URL(filePath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName

    private var cleanable: Int64 { state.cleaner.bytes(of: state.cleaner.tasks) }

    private var slices: [Slice] {
        guard let disk = state.disk else { return [] }
        let cleanable = min(cleanable, disk.used)
        return [
            Slice(id: L("Kullanılan", "Used"), bytes: disk.used - cleanable, color: Theme.mute.opacity(0.45)),
            Slice(id: L("Temizlenebilir", "Cleanable"), bytes: cleanable, color: Theme.acc, minimumShare: cleanable > 0 ? 0.015 : 0),
            Slice(id: L("Boş", "Free"), bytes: disk.available, color: Theme.line),
        ]
    }

    private var categories: [TaskCategory] {
        TaskCategory.allCases.filter { !state.cleaner.tasks(in: $0).isEmpty }
    }

    private func bytes(of category: TaskCategory) -> Int64 {
        state.cleaner.bytes(of: state.cleaner.tasks(in: category))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Genel Bakış", "Overview"), subtitle: diskSubtitle, badge: Self.volumeName, isBusy: state.cleaner.isScanning) {
                    Button {
                        state.refreshDisk()
                        Task { await state.cleaner.scan() }
                    } label: {
                        Label(L("Yenile", "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.pill)
                    .disabled(state.cleaner.isBusy)
                }

                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        storageCard.frame(width: 320)
                        categoryCard
                    }
                    actionCard
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: Kartlar

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(L("Depolama", "Storage"))
            Chart(slices) { slice in
                SectorMark(angle: .value("Boyut", chartValue(slice)), innerRadius: .ratio(0.82), angularInset: 1.5)
                    .foregroundStyle(slice.color)
                    .cornerRadius(6)
            }
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(state.disk.map { Format.bytes($0.available) } ?? "—").font(Theme.mono(26))
                    SectionLabel(L("Boş", "Free"))
                }
            }
            .frame(width: 180, height: 180)
            .frame(maxWidth: .infinity)

            // Eşit sütunlar yerine içeriğe göre genişlik: L("Temizlenebilir", "Cleanable") yanındaki sütuna taşmasın.
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    if index > 0 { Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.id).font(.system(size: 11)).foregroundStyle(Theme.mute).lineLimit(1)
                        }
                        Text(Format.bytes(slice.bytes)).font(Theme.mono(12))
                    }
                    .fixedSize()
                }
            }
            .padding(12)
            .background(Theme.content, in: RoundedRectangle(cornerRadius: 12))
        }
        .card(padding: 20)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L("Kategoriye göre", "By category"))
            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    if index > 0 { RowDivider(leading: 40) }
                    HStack(spacing: 12) {
                        Plate(icon: category.icon, color: category.plate)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title).font(.system(size: 14, weight: .medium))
                            Text(state.cleaner.tasks(in: category).map { $0.shortTitle }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.mute)
                                .lineLimit(1)
                            ShareBar(share: share(of: category))
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 8)
                        if bytes(of: category) == 0 {
                            Chip(text: L("Temiz", "Clean"), background: Theme.okSoft, foreground: Theme.onOk)
                        } else {
                            Text(Format.bytes(bytes(of: category)))
                                .font(Theme.mono(12))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(Theme.line))
                        }
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .card(padding: 20)
    }

    /// Kategorinin toplam temizlenebilir alan içindeki payı.
    private func share(of category: TaskCategory) -> Double {
        let total = categories.reduce(Int64(0)) { $0 + bytes(of: $1) }
        return total > 0 ? Double(bytes(of: category)) / Double(total) : 0
    }

    private func chartValue(_ slice: Slice) -> Double {
        let total = Double(max(slices.reduce(Int64(0)) { $0 + $1.bytes }, 1))
        return max(Double(slice.bytes), total * slice.minimumShare)
    }

    private var actionCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.acc).frame(width: 7, height: 7)
                    Text(state.cleaner.isScanning ? L("Taranıyor…", "Scanning…") : L("\(Format.bytes(cleanable)) temizlenebilir alan bulundu.", "Found \(Format.bytes(cleanable)) of cleanable space."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mute)
                }
                HStack(spacing: 10) {
                    Button(L("Büyük Dosyaları Bul", "Find Large Files")) { navigate(.largeFiles) }.buttonStyle(.pill)
                    Button(L("Kalıntıları Bul", "Find Leftovers")) { navigate(.leftovers) }.buttonStyle(.pill)
                    Button { navigate(.cleanup) } label: {
                        Label(L("Akıllı Temizlik", "Smart Cleanup"), systemImage: "arrow.right").labelStyle(TrailingIcon())
                    }
                    .buttonStyle(.pill)
                }
            }
            Spacer(minLength: 8)
            quickCleanButton
        }
        .card(padding: 20)
    }

    /// Widget'la aynı iş: Tek Tık ön ayarını çalıştırır, ilerleyişi ve sonucu düğmenin üzerinde gösterir.
    private var quickCleanButton: some View {
        let cleaning = state.cleaner.isCleaning
        return VStack(alignment: .trailing, spacing: 6) {
            Button {
                Task { await runQuickClean() }
            } label: {
                HStack(spacing: 8) {
                    if cleaning {
                        ProgressView().controlSize(.small).tint(Theme.onAcc)
                        Text(L("Temizleniyor…", "Cleaning…"))
                    } else if let freed = cleanResult {
                        Image(systemName: "checkmark.circle.fill")
                        Text(L("\(Format.bytes(freed)) boşaltıldı", "\(Format.bytes(freed)) freed"))
                            .contentTransition(.numericText())
                    } else {
                        Image(systemName: "sparkles")
                        Text(L("Tek Tık Temizle", "One-Click Clean"))
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .id(cleaning ? "cleaning" : (cleanResult == nil ? "idle" : "done"))
            }
            .buttonStyle(PillButton(primary: cleanResult == nil, large: true))
            .disabled(cleaning || state.presetTasks.isEmpty)
            .help(L("Ayarlar'daki Tek Tık Temizlik ön ayarını çalıştırır (widget'la aynı)",
                    "Runs the One-Click Clean preset from Settings (same as the widget)"))
            Text(L("\(state.presetTasks.count) görev · ≈ \(Format.bytes(state.presetBytes))",
                   "\(state.presetTasks.count) tasks · ≈ \(Format.bytes(state.presetBytes))"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.mute)
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func runQuickClean() async {
        let freed = await state.quickClean()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { cleanResult = freed }
        try? await Task.sleep(for: .seconds(6))
        withAnimation(.easeOut) { cleanResult = nil }
    }

    private var diskSubtitle: String {
        guard let disk = state.disk else { return L("Disk bilgisi alınamadı", "Disk information unavailable") }
        return L("\(Format.bytes(disk.used)) / \(Format.bytes(disk.total)) kullanılıyor · \(Format.bytes(cleanable)) temizlenebilir", "\(Format.bytes(disk.used)) of \(Format.bytes(disk.total)) used · \(Format.bytes(cleanable)) cleanable")
    }
}

/// İkonu metnin sağına koyan etiket stili ("Git →").
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// Kategori satırındaki ince pay çubuğu (sarı yalnızca dolgu olarak).
private struct ShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                if share > 0 {
                    Capsule().fill(Theme.acc).frame(width: max(4, geo.size.width * share))
                }
            }
        }
        .frame(height: 4)
    }
}
