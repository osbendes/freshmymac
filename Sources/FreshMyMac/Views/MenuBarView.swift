import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let cleaner = state.cleaner

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAcc)
                    .frame(width: 22, height: 22)
                    .background(Theme.acc, in: RoundedRectangle(cornerRadius: 6))
                Text("FreshMyMac").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if cleaner.isBusy { ProgressView().controlSize(.small) }
            }

            if let disk = state.disk {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel("Disk")
                        Spacer()
                        Text(L("\(Format.bytes(disk.available)) boş / \(Format.bytes(disk.total))", "\(Format.bytes(disk.available)) free of \(Format.bytes(disk.total))"))
                            .font(.system(size: 11)).foregroundStyle(Theme.mute)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(Theme.acc)
                                .frame(width: geo.size.width * CGFloat(disk.used) / CGFloat(max(disk.total, 1)))
                        }
                    }
                    .frame(height: 6)
                }
            }

            HStack {
                Text(L("Tek Tık ile temizlenebilir", "Cleanable with One-Click")).font(.system(size: 12))
                Spacer()
                Text(Format.bytes(state.presetBytes)).font(Theme.mono(13))
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))

            if let message = state.lastActionMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.mute)
            }

            Button {
                Task { await state.quickClean() }
            } label: {
                Label(L("Tek Tık Temizlik", "One-Click Clean"), systemImage: "sparkles")
            }
            .buttonStyle(PillButton(primary: true, large: true, fill: true))
            .disabled(cleaner.isBusy || state.presetTasks.isEmpty)
            .help(L("Ayarlar'daki Tek Tık Temizlik ön ayarını çalıştırır", "Runs the One-Click Clean preset from Settings"))

            Button {
                Task { await state.flushInternetCache() }
            } label: {
                Label(L("İnternet Önbelleğini Temizle", "Clear Internet Cache"), systemImage: "network")
            }
            .buttonStyle(PillButton(large: true, fill: true))
            .disabled(cleaner.isBusy)
            .help(L("DNS ve ARP önbelleğini sıfırlar (ipconfig /flushdns). Yönetici şifresi istenir.", "Resets the DNS and ARP caches (ipconfig /flushdns). Requires an administrator password."))

            RowDivider()

            HStack {
                Button(L("Pencereyi Aç", "Open Window")) {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button(L("Çıkış", "Quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.link)
        }
        .foregroundStyle(Theme.fg)
        .padding(16)
        .frame(width: 300)
        .background(Theme.bg)
    }
}
