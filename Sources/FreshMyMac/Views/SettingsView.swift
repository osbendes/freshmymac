import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(AppearanceMode.key) private var appearance: AppearanceMode = .system
    @State private var openCategories: Set<TaskCategory> = []

    var body: some View {
        @Bindable var settings = state.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Ayarlar", "Settings"), subtitle: L("Görünüm, Tek Tık Temizlik ve zamanlama", "Appearance, One-Click Clean and scheduling")) {}

                VStack(alignment: .leading, spacing: 16) {
                    appearanceCard
                    presetCard(settings)
                    generalCard(settings)
                    scheduleCard(settings)
                    permissionsCard
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .onChange(of: appearance) { appearance.apply() }
        .onChange(of: settings.presetTaskIDs) { state.publishWidgetStatus() }
        .onChange(of: settings.language) { state.publishWidgetStatus() }
    }

    // MARK: Kartlar

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L("Görünüm", "Appearance"))
            HStack {
                Text(L("Tema", "Theme")).font(.system(size: 13))
                Spacer()
                Segmented(selection: $appearance, options: AppearanceMode.allCases, title: \.title)
            }
            RowDivider()
            HStack {
                Text(L("Dil", "Language")).font(.system(size: 13))
                Spacer()
                Segmented(selection: Bindable(state.settings).language, options: AppLanguage.allCases, title: \.title)
            }
        }
        .card(padding: 18)
    }

    private func presetCard(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(L("Tek Tık Temizlik", "One-Click Clean"))
                Spacer()
                Text(Format.bytes(state.presetBytes)).font(Theme.mono(12)).foregroundStyle(Theme.mute)
            }
            Text(L("Masaüstü widget'ı, menü çubuğundaki \"Tek Tık Temizlik\" ve zamanlanmış temizlik bu görevleri çalıştırır. Widget eklemek için masaüstüne sağ tıklayıp \"Widget'ları Düzenle…\" seçin ve FreshMyMac'i arayın.", "The desktop widget, \"One-Click Clean\" in the menu bar and scheduled cleanup run these tasks. To add the widget, right-click the desktop, choose \"Edit Widgets…\" and search for FreshMyMac."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.mute)
            SelectAllToggle(ids: state.cleaner.tasks.map(\.id), selection: $settings.presetTaskIDs)
                .padding(.vertical, 4)
            ForEach(TaskCategory.allCases, id: \.self) { category in
                let tasks = state.cleaner.tasks(in: category)
                if !tasks.isEmpty {
                    RowDivider()
                    let isOpen = openCategories.contains(category)
                    HStack(spacing: 10) {
                        SelectAllToggle(title: "", ids: tasks.map(\.id), selection: $settings.presetTaskIDs)
                        Plate(icon: category.icon, color: category.plate, size: 24)
                        Text(category.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            openCategories.formSymmetricDifference([category])
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                                .foregroundStyle(Theme.mute)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                    if isOpen {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(tasks) { task in
                                Toggle(isOn: .membership(task.id, in: $settings.presetTaskIDs)) {
                                    HStack(spacing: 6) {
                                        Text(task.title)
                                        if task.requiresAdmin {
                                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.mute)
                                        }
                                    }
                                }
                                .toggleStyle(.check)
                            }
                        }
                        .padding(.leading, 62)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private func generalCard(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L("Genel", "General"))
            Toggle(L("Menü çubuğunda göster", "Show in menu bar"), isOn: $settings.showMenuBarIcon)
            RowDivider()
            Toggle(L("Oturum açılışında başlat", "Launch at login"), isOn: $settings.launchAtLogin)
                .disabled(!AppEnvironment.isBundled)
            if !AppEnvironment.isBundled {
                Text(L("Oturum açılışı, bildirimler ve widget yalnızca .app paketiyle çalışır (scripts/build-app.sh).", "Launch at login, notifications and the widget only work in the .app bundle (scripts/build-app.sh)."))
                    .font(.system(size: 12)).foregroundStyle(Theme.mute)
            }
            if let error = settings.launchAtLoginError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.onWarn)
            }
        }
        .toggleStyle(.yellowSwitch)
        .font(.system(size: 13))
        .card(padding: 18)
    }

    private func scheduleCard(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L("Zamanlanmış temizlik", "Scheduled cleanup"))
            Toggle(L("Otomatik temizlik", "Automatic cleanup"), isOn: $settings.autoCleanEnabled)
                .toggleStyle(.yellowSwitch)
            RowDivider()
            HStack {
                Text(L("Sıklık", "Frequency"))
                Spacer()
                Segmented(selection: $settings.autoCleanInterval, options: AutoCleanInterval.allCases, title: \.title)
                    .disabled(!settings.autoCleanEnabled)
            }
            RowDivider()
            LabeledContent(L("Son çalışma", "Last run"), value: Format.dateTime(settings.lastAutoClean))
            LabeledContent(L("Sonraki çalışma", "Next run"), value: Format.dateTime(settings.nextAutoClean))
            Text(L("Tek Tık Temizlik ön ayarı çalışır. Yönetici şifresi isteyen görevler (internet önbelleği, bellek) ve açık tarayıcıya bağlı görevler otomatik modda atlanır. Uygulamanın (menü çubuğunda) açık olması gerekir.", "Runs the One-Click Clean preset. Tasks that need an administrator password (internet cache, memory) and tasks that depend on a closed browser are skipped in automatic mode. The app must be running (in the menu bar)."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.mute)
        }
        .font(.system(size: 13))
        .card(padding: 18)
    }

    private var permissionsCard: some View {
        HStack(spacing: 12) {
            Plate(icon: "lock.shield", color: Theme.lavender)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Tam Disk Erişimi", "Full Disk Access")).font(.system(size: 13, weight: .medium))
                Text(L("Çöp Kutusu, Safari geçmişi ve bazı kapsayıcılar için gereklidir.", "Required for the Trash, Safari history and some containers."))
                    .font(.system(size: 12)).foregroundStyle(Theme.mute)
            }
            Spacer()
            Button(L("Ayarları Aç", "Open Settings")) { SystemSettings.openFullDiskAccess() }
                .buttonStyle(.pill)
        }
        .card(padding: 18)
    }
}

/// Seçili seçeneği sarı kapsülle gösteren bölümlü seçici.
struct Segmented<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button(option[keyPath: title]) { selection = option }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: active ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(active ? Theme.onAcc : Theme.mute)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(active ? Theme.acc : .clear, in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .padding(3)
        .background(Theme.tint, in: Capsule())
        .opacity(enabled ? 1 : 0.45)
    }
}
