import SwiftUI

struct LeftoversView: View {
    @Environment(AppState.self) private var state
    @State private var confirmTrash = false
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var model = state.leftovers

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Uygulama Kalıntıları", "App Leftovers"), subtitle: subtitle,
                             badge: model.hasScanned ? L("\(model.groups.count) uygulama", "\(model.groups.count) apps") : nil, isBusy: model.isScanning) {
                    Button { Task { await model.scan() } } label: {
                        Label(L("Tara", "Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.pill)
                    .disabled(model.isScanning)
                    Button { confirmTrash = true } label: {
                        Label(L("Çöp Kutusu'na Taşı", "Move to Trash"), systemImage: "trash")
                    }
                    .buttonStyle(.pillPrimary)
                    .disabled(model.selection.isEmpty)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if model.groups.isEmpty {
                        EmptyState(
                            title: model.hasScanned ? L("Kalıntı bulunamadı", "No leftovers found") : L("Henüz taranmadı", "Not scanned yet"),
                            icon: "shippingbox",
                            message: L("Kaldırılmış uygulamaların ~/Library altında bıraktığı tercih, önbellek ve destek dosyalarını bulur.", "Finds preferences, caches and support files that uninstalled apps left behind in ~/Library.")
                        )
                        .card()
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SelectAllToggle(ids: model.allIDs, selection: $model.selection)
                                Spacer()
                            }
                            .padding(.bottom, 4)
                            ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                                if index > 0 { RowDivider(leading: 70) }
                                groupRow(group, selection: $model.selection)
                            }
                        }
                        .card(padding: 18)

                        Text(L("Aynı geliştiricinin kurulu bir uygulaması varsa o geliştiriciye ait öğeler güvenlik için listelenmez. Taşımadan önce listeyi gözden geçirin.", "For safety, items from a developer that still has an installed app are not listed. Review the list before moving anything."))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mute)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .confirmationDialog(L("\(model.selection.count) uygulamanın kalıntıları Çöp Kutusu'na taşınsın mı?", "Move leftovers of \(model.selection.count) apps to the Trash?"), isPresented: $confirmTrash) {
            Button(L("Taşı", "Move"), role: .destructive) {
                Task {
                    await model.trashSelected()
                    state.refreshDisk()
                }
            }
        } message: {
            Text(L("Dosyalar Çöp Kutusu'ndan geri alınabilir.", "Files can be restored from the Trash."))
        }
    }

    private func groupRow(_ group: LeftoverGroup, selection: Binding<Set<String>>) -> some View {
        let isOpen = expanded.contains(group.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle(isOn: .membership(group.id, in: selection)) {}
                    .toggleStyle(.check)
                    .accessibilityLabel(group.id)
                Plate(icon: "shippingbox", color: Theme.peach)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.id).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(L("\(group.files.count) öğe", "\(group.files.count) items")).font(.system(size: 11)).foregroundStyle(Theme.mute)
                }
                Spacer(minLength: 8)
                Text(Format.bytes(group.totalSize)).font(Theme.mono(13))
                Button {
                    expanded.formSymmetricDifference([group.id])
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Theme.mute)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isOpen ? L("Dosyaları gizle", "Hide files") : L("Dosyaları göster", "Show files"))
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.files) { file in
                        HStack {
                            Text(file.url.path(percentEncoded: false)
                                .replacingOccurrences(of: FileUtils.home.path(percentEncoded: false), with: "~/"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(file.size)).monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mute)
                        .contextMenu { Button(L("Finder'da Göster", "Show in Finder")) { SystemSettings.reveal(file.url) } }
                    }
                }
                .padding(10)
                .background(Theme.content, in: RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 70)
            }
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let model = state.leftovers
        if let status = model.status { return status }
        if !model.hasScanned { return L("Kaldırılmış uygulamalardan geride kalan dosyalar", "Files left behind by uninstalled apps") }
        let total = model.groups.reduce(0) { $0 + $1.totalSize }
        if model.selection.isEmpty { return L("\(model.groups.count) uygulama · \(Format.bytes(total))", "\(model.groups.count) apps · \(Format.bytes(total))") }
        return L("\(model.selection.count) seçildi · \(Format.bytes(model.selectedBytes))", "\(model.selection.count) selected · \(Format.bytes(model.selectedBytes))")
    }
}
