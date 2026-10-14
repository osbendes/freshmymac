import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    @State private var confirmTrash = false

    var body: some View {
        @Bindable var model = state.largeFiles

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Büyük ve Eski Dosyalar", "Large & Old Files"), subtitle: subtitle,
                             badge: model.hasScanned ? L("\(model.results.count) dosya", "\(model.results.count) files") : nil, isBusy: model.isScanning) {
                    Button { Task { await model.scan() } } label: {
                        Label(L("Tara", "Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.pill)
                    .disabled(model.isScanning || model.scopes.isEmpty)
                    Button { confirmTrash = true } label: {
                        Label(L("Çöp Kutusu'na Taşı", "Move to Trash"), systemImage: "trash")
                    }
                    .buttonStyle(.pillPrimary)
                    .disabled(model.selection.isEmpty)
                }

                VStack(spacing: 16) {
                    filterCard(model)
                    if model.results.isEmpty {
                        EmptyState(
                            title: model.hasScanned ? L("Eşleşen dosya yok", "No matching files") : L("Henüz taranmadı", "Not scanned yet"),
                            icon: "doc.text.magnifyingglass",
                            message: model.hasScanned ? L("Ölçütleri değiştirip tekrar deneyin.", "Change the criteria and try again.") : L("Ölçütleri seçip Tara'ya basın.", "Choose your criteria and press Scan.")
                        )
                        .card()
                    } else {
                        HStack {
                            SelectAllToggle(ids: model.allIDs, selection: $model.selection)
                            Spacer()
                            if !model.selection.isEmpty {
                                Text(L("\(model.selection.count) öğe seçili · \(Format.bytes(model.selectedBytes))", "\(model.selection.count) items selected · \(Format.bytes(model.selectedBytes))"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.mute)
                            }
                        }
                        .padding(.horizontal, 4)
                        ForEach(model.kinds) { kind in
                            kindCard(kind, files: model.files(of: kind), selection: $model.selection)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .confirmationDialog(L("\(model.selection.count) dosya Çöp Kutusu'na taşınsın mı?", "Move \(model.selection.count) files to the Trash?"), isPresented: $confirmTrash) {
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

    private func filterCard(_ model: LargeFilesViewModel) -> some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            SectionLabel(L("Filtre", "Filter"))
            ForEach(LargeFileMode.allCases) { mode in
                Button(mode.title) { model.mode = mode }
                    .buttonStyle(PillButton(primary: model.mode == mode))
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 18)
            Stepper(L("En az \(model.minSizeMB) MB", "At least \(model.minSizeMB) MB"), value: $model.minSizeMB, in: 0...10_000, step: 50)
                .font(.system(size: 12))
            if model.mode == .old {
                Stepper(L("\(model.olderThanDays) günden eski", "Older than \(model.olderThanDays) days"), value: $model.olderThanDays, in: 7...730, step: 7)
                    .font(.system(size: 12))
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(LargeFileScope.allCases) { scope in
                    Toggle(scope.title, isOn: .membership(scope, in: $model.scopes))
                }
                Divider()
                Button(L("Tüm klasörler", "All folders")) { model.scopes = Set(LargeFileScope.allCases) }
                Button(L("İndirilenler'de 30 günden eski her şey", "Everything in Downloads older than 30 days")) { model.applyOldDownloadsPreset() }
            } label: {
                Label(L("Klasörler (\(model.scopes.count))", "Folders (\(model.scopes.count))"), systemImage: "folder")
            }
            .menuStyle(.button)
            .buttonStyle(.pill)
            .fixedSize()
        }
        .card(padding: 14)
    }

    private func kindCard(_ kind: FileKind, files: [FoundFile], selection: Binding<Set<URL>>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SelectAllToggle(title: "", ids: files.map(\.url), selection: selection)
                SectionLabel(kind.title)
                Spacer()
                Text(L("\(files.count) dosya · \(Format.bytes(files.reduce(0) { $0 + $1.size }))", "\(files.count) files · \(Format.bytes(files.reduce(0) { $0 + $1.size }))"))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.mute)
            }
            .padding(.bottom, 4)
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if index > 0 { RowDivider(leading: 70) }
                row(file, selection: selection)
            }
        }
        .card(padding: 18)
    }

    private func row(_ file: FoundFile, selection: Binding<Set<URL>>) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: .membership(file.url, in: selection)) {}
                .toggleStyle(.check)
                .accessibilityLabel(file.name)
            Plate(fileName: file.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path(percentEncoded: false)
                    .replacingOccurrences(of: FileUtils.home.path(percentEncoded: false), with: "~/"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mute)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Format.date(file.date)).font(.system(size: 12)).foregroundStyle(Theme.mute)
                .frame(width: 90, alignment: .trailing)
            Text(Format.bytes(file.size)).font(Theme.mono(13))
                .frame(width: 80, alignment: .trailing)
            Button { SystemSettings.reveal(file.url) } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
            }
            .buttonStyle(.plain)
            .help(L("Finder'da göster", "Show in Finder"))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { selection.wrappedValue.formSymmetricDifference([file.url]) }
    }

    private var subtitle: String {
        let model = state.largeFiles
        if let status = model.status { return status }
        if model.selection.isEmpty { return L("Diskte en çok yer kaplayan ya da uzun süredir açılmayan dosyalar", "Files that take the most space or haven't been opened in a long time") }
        return L("\(model.selection.count) dosya seçildi · \(Format.bytes(model.selectedBytes))", "\(model.selection.count) files selected · \(Format.bytes(model.selectedBytes))")
    }
}
