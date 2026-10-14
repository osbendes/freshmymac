import SwiftUI

/// İlk açılışta gerekli izinleri bir kez isteyen karşılama penceresi.
struct OnboardingView: View {
    static let doneKey = "onboardingDone"

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Plate(icon: "sparkles", color: Theme.acc, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("FreshMyMac'e hoş geldiniz", "Welcome to FreshMyMac"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(L("Temizliklerin her seferinde şifre sormadan çalışması için izinleri bir kez verin.",
                           "Grant permissions once so cleanups run without asking for your password every time."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                AdminPermissionRow()
                RowDivider()
                FullDiskAccessRow()
            }
            .card(padding: 18)

            HStack {
                Text(L("İzinleri daha sonra Ayarlar › İzinler'den değiştirebilirsiniz.",
                       "You can change these later in Settings › Permissions."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mute)
                Spacer()
                Button(state.privilegesGranted ? L("Bitti", "Done") : L("Daha Sonra", "Later")) { finish() }
                    .buttonStyle(PillButton(primary: state.privilegesGranted, large: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.content)
        .foregroundStyle(Theme.fg)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        dismiss()
    }
}

/// Yönetici izni: verilmemişse "İzin Ver", verilmişse durum ve "Kaldır".
struct AdminPermissionRow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Plate(icon: "key", color: Theme.peach)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L("Yönetici izni", "Administrator permission")).font(.system(size: 13, weight: .medium))
                    if state.privilegesGranted {
                        Chip(text: L("Verildi", "Granted"), background: Theme.okSoft, foreground: Theme.onOk)
                    }
                }
                Text(L("İnternet önbelleği ve bellek temizliği şifre sormadan çalışır. Yalnızca bu komutlara izin verilir.",
                       "Internet cache and memory cleanup run without a password. Only these commands are allowed."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mute)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = state.privilegeError {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.onWarn)
                }
            }
            Spacer(minLength: 8)
            if state.isChangingPrivileges {
                ProgressView().controlSize(.small)
            } else if state.privilegesGranted {
                Button(L("Kaldır", "Remove")) { Task { await state.revokePrivileges() } }
                    .buttonStyle(.pill)
            } else {
                Button(L("İzin Ver", "Grant")) { Task { await state.grantPrivileges() } }
                    .buttonStyle(.pillPrimary)
            }
        }
    }
}

/// Tam Disk Erişimi: macOS bunu yalnızca Sistem Ayarları'ndan verdirir.
struct FullDiskAccessRow: View {
    @Environment(AppState.self) private var state
    /// Ayarlar'dan dönüldüğünde durumu yeniden okumak için.
    @State private var granted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Plate(icon: "lock.shield", color: Theme.lavender)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L("Tam Disk Erişimi", "Full Disk Access")).font(.system(size: 13, weight: .medium))
                    if granted {
                        Chip(text: L("Verildi", "Granted"), background: Theme.okSoft, foreground: Theme.onOk)
                    }
                }
                Text(L("Çöp Kutusu, Safari geçmişi ve bazı kapsayıcılar için gereklidir. Listede FreshMyMac'i açın.",
                       "Needed for the Trash, Safari history and some containers. Turn on FreshMyMac in the list."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !granted {
                Button(L("Ayarları Aç", "Open Settings")) { SystemSettings.openFullDiskAccess() }
                    .buttonStyle(.pill)
            }
        }
        .onAppear { granted = state.hasFullDiskAccess }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = state.hasFullDiskAccess
        }
    }
}
