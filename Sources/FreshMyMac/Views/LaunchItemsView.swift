import SwiftUI

struct LaunchItemsView: View {
    @Environment(AppState.self) private var state
    @State private var confirmRemoval = false

    var body: some View {
        @Bindable var model = state.launchItems

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Açılış Öğeleri", "Launch Items"), subtitle: subtitle, isBusy: model.isScanning || model.isRemoving) {
                    Button(L("Oturum Açma Öğeleri…", "Login Items…")) { SystemSettings.openLoginItems() }
                        .buttonStyle(.pill)
                        .help(L("Sistem Ayarları'ndaki oturum açma öğelerini açar", "Opens Login Items in System Settings"))
                    Button { Task { await model.scan() } } label: {
                        Label(L("Yenile", "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.pill)
                    .disabled(model.isScanning)
                    Button(L("Seçilenleri Kaldır", "Remove Selected")) { confirmRemoval = true }
                        .buttonStyle(.pillPrimary)
                        .disabled(model.selection.isEmpty || model.isRemoving)
                }

                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        SelectAllToggle(ids: model.allIDs, selection: $model.selection)
                        Button(L("Sahipsizleri seç", "Select orphans")) { model.selectOrphans() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.link)
                            .disabled(!model.items.contains(where: \.isOrphaned))
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                        let items = model.items(in: scope)
                        if !items.isEmpty { scopeCard(scope, items, selection: $model.selection) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .task { if model.items.isEmpty { await model.scan() } }
        .confirmationDialog(L("\(model.selection.count) öğe kaldırılsın mı?", "Remove \(model.selection.count) items?"), isPresented: $confirmRemoval) {
            Button(L("Durdur ve Kaldır", "Stop and Remove"), role: .destructive) {
                Task { await model.removeSelected() }
            }
        } message: {
            Text(model.selectionRequiresAdmin
                 ? L("Öğeler durdurulup plist dosyaları Çöp Kutusu'na taşınacak. Yönetici şifresi bir kez istenecek.", "The items will be stopped and their plist files moved to the Trash. You will be asked for your administrator password once.")
                 : L("Öğeler durdurulup plist dosyaları Çöp Kutusu'na taşınacak.", "The items will be stopped and their plist files moved to the Trash."))
        }
    }

    private func scopeCard(_ scope: LaunchItem.Scope, _ items: [LaunchItem], selection: Binding<Set<URL>>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SelectAllToggle(title: "", ids: items.map(\.id), selection: selection)
                SectionLabel(scope.title)
                if scope.requiresAdmin {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.mute)
                        .help(L("Kaldırmak yönetici şifresi gerektirir", "Removing requires an administrator password"))
                }
                Spacer()
                Text("\(items.count)").font(Theme.mono(12)).foregroundStyle(Theme.mute)
            }
            .padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider(leading: 70) }
                row(item, selection: selection)
            }
        }
        .card(padding: 18)
    }

    private var subtitle: String {
        let model = state.launchItems
        if let status = model.status { return status }
        let orphans = model.items.filter(\.isOrphaned).count
        if model.selection.isEmpty { return L("\(model.items.count) arka plan öğesi · \(orphans) sahipsiz", "\(model.items.count) background items · \(orphans) orphaned") }
        return L("\(model.selection.count) öğe seçildi", "\(model.selection.count) items selected")
    }

    private func row(_ item: LaunchItem, selection: Binding<Set<URL>>) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: .membership(item.id, in: selection)) {}
                .toggleStyle(.check)
                .accessibilityLabel(item.label)
            Plate(icon: "bolt", color: item.isOrphaned ? Theme.rose : Theme.sky)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(item.isLoaded == true ? Theme.onOk : Theme.mute.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
                .help(item.isLoaded.map { $0 ? L("Çalışıyor/yüklü", "Running/loaded") : L("Yüklü değil", "Not loaded") } ?? L("Durum bilinmiyor", "Status unknown"))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if item.isOrphaned {
                        Chip(text: L("Program bulunamadı", "Program missing"), background: Theme.warnSoft, foreground: Theme.onWarn)
                    }
                }
                Text(item.program ?? item.plist.path(percentEncoded: false))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mute)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button { SystemSettings.reveal(item.plist) } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
            }
            .buttonStyle(.plain)
            .help(L("Finder'da göster", "Show in Finder"))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { selection.wrappedValue.formSymmetricDifference([item.id]) }
    }
}
