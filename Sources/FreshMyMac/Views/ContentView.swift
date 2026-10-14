import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case overview, cleanup, largeFiles, leftovers, launchItems, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: L("Genel Bakış", "Overview")
        case .cleanup: L("Akıllı Temizlik", "Smart Cleanup")
        case .largeFiles: L("Büyük ve Eski Dosyalar", "Large & Old Files")
        case .leftovers: L("Uygulama Kalıntıları", "App Leftovers")
        case .launchItems: L("Açılış Öğeleri", "Launch Items")
        case .settings: L("Ayarlar", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .cleanup: "sparkles"
        case .largeFiles: "doc.zipper"
        case .leftovers: "shippingbox"
        case .launchItems: "bolt"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    /// Açılış ekranı `-screen cleanup` gibi bir başlatma argümanıyla seçilebilir (ekran görüntüleri için).
    @State private var screen = Screen(rawValue: UserDefaults.standard.string(forKey: "screen") ?? "") ?? .overview

    @State private var showOnboarding = false

    var body: some View {
        // Metinler `L(...)` ile çözüldüğü için dil değişince alt görünümler yeniden kurulur;
        // `screen` burada tutulduğundan açık ekran korunur.
        // Dil ya da yönetici izni değişince (kilit simgeleri) alt görünümler yeniden kurulur.
        let refreshKey = "\(state.settings.language.rawValue)-\(state.privilegesGranted)"
        HStack(spacing: 0) {
            Sidebar(screen: $screen).id(refreshKey)
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                switch screen {
                case .overview: OverviewView(navigate: { screen = $0 })
                case .cleanup: CleanupView()
                case .largeFiles: LargeFilesView()
                case .leftovers: LeftoversView()
                case .launchItems: LaunchItemsView()
                case .settings: SettingsView()
                }
            }
            .id(refreshKey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.content)
        }
        .environment(\.locale, L10n.locale)
        .sheet(isPresented: $showOnboarding) { OnboardingView().environment(state) }
        .onChange(of: state.privilegesChecked) { _, checked in
            // İlk açılışta, izin verilmemişse bir kez gösterilir (ekran görüntüsü modunda hiç).
            let snapshotting = UserDefaults.standard.string(forKey: "snapshot") != nil || Demo.isOn
            if checked, !state.privilegesGranted, !snapshotting,
               !UserDefaults.standard.bool(forKey: OnboardingView.doneKey) {
                showOnboarding = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(Theme.fg)
    }
}

private struct Sidebar: View {
    @Binding var screen: Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onAcc)
                    .frame(width: 28, height: 28)
                    .background(Theme.acc, in: RoundedRectangle(cornerRadius: 8))
                Text("FreshMyMac").font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 6)
            .padding(.top, 44) // Trafik ışıklarının altı.

            VStack(spacing: 2) {
                ForEach(Screen.allCases) { item in
                    SidebarItem(item: item, isActive: item == screen) { screen = item }
                }
            }
            Spacer()
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text(L("Sürüm \(version)", "Version \(version)"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.mute)
                    .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }
}

private struct SidebarItem: View {
    let item: Screen
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(item.title).lineLimit(1)
            } icon: {
                Image(systemName: item.icon).frame(width: 20)
            }
            .font(.system(size: 13, weight: isActive ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isActive ? Theme.onAcc : (hovering ? Theme.fg : Theme.mute))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Theme.acc : (hovering ? Theme.card : .clear), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Ekranların üst kısmında kullanılan başlık + eylem satırı.
struct ScreenHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    var badge: String?
    var isBusy = false
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                    if let badge { Chip(text: badge) }
                }
                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.mute)
                    .monospacedDigit()
            }
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            actions
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 18)
    }
}

/// Liste boşken gösterilen sade durum kartı.
struct EmptyState: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Plate(icon: icon, color: Theme.acc, size: 48)
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
