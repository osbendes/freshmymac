import SwiftUI

struct CleanupView: View {
    @Environment(AppState.self) private var state
    @State private var confirmClean = false

    private var model: CleanerViewModel { state.cleaner }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: L("Akıllı Temizlik", "Smart Cleanup"), subtitle: subtitle, badge: badge, isBusy: model.isBusy) {
                    Button { Task { await model.scan() } } label: {
                        Label(L("Tara", "Scan"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.pill)
                    .disabled(model.isBusy)
                    Button { confirmClean = true } label: {
                        Label(L("Temizle", "Clean"), systemImage: "sparkles")
                    }
                    .buttonStyle(.pillPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || model.selection.isEmpty)
                }

                VStack(spacing: 16) {
                    summaryCard
                    if !model.log.isEmpty { logCard }
                    ForEach(TaskCategory.allCases, id: \.self) { category in
                        let tasks = model.tasks(in: category)
                        if !tasks.isEmpty { categoryCard(category, tasks) }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .confirmationDialog(
            L("Seçili \(model.selectedTasks.count) temizlik çalıştırılsın mı?", "Run \(model.selectedTasks.count) selected cleanups?"),
            isPresented: $confirmClean
        ) {
            Button(L("Temizle", "Clean"), role: .destructive) {
                Task {
                    await model.clean()
                    state.refreshDisk()
                }
            }
        } message: {
            Text(L("Silinen dosyalar geri alınamaz. Yönetici gerektiren işlemler için şifreniz bir kez sorulacak.", "Deleted files cannot be recovered. You will be asked for your password once for tasks that need administrator rights."))
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.fg)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.acc, lineWidth: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("\(model.selection.count) / \(model.tasks.count) görev seçili", "\(model.selection.count) / \(model.tasks.count) tasks selected"))
                    .font(.system(size: 14, weight: .medium))
                Text(L("Yalnızca seçtiğiniz görevlerin konumları temizlenir. Silinen dosyalar geri alınamaz.", "Only the locations of the tasks you select are cleaned. Deleted files cannot be recovered."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mute)
            }
            Spacer(minLength: 8)
            SelectAllToggle(ids: model.tasks.map(\.id), selection: Bindable(model).selection)
                .disabled(model.isBusy)
        }
        .card(padding: 16)
    }

    private func categoryCard(_ category: TaskCategory, _ tasks: [CleanupTask]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SelectAllToggle(title: "", ids: tasks.map(\.id), selection: Bindable(model).selection)
                    .disabled(model.isBusy)
                SectionLabel(category.title)
                Spacer()
                Text(Format.bytes(model.bytes(of: tasks.filter { model.selection.contains($0.id) })))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.mute)
            }
            .padding(.bottom, 4)
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { RowDivider(leading: 70) }
                TaskRow(
                    task: task,
                    isSelected: model.selection.contains(task.id),
                    state: model.scanStates[task.id] ?? .idle,
                    toggle: { model.toggle(task) }
                )
                .disabled(model.isBusy)
            }
        }
        .card(padding: 18)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L("Son temizlik", "Last cleanup"))
            ForEach(model.log) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Plate(icon: entry.success ? "checkmark" : "exclamationmark",
                          color: entry.success ? Theme.mint : Theme.peach, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.system(size: 13, weight: .medium))
                        Text(entry.detail).font(.system(size: 12)).foregroundStyle(Theme.mute)
                    }
                }
            }
        }
        .card(padding: 18)
    }

    private var badge: String? {
        if model.isCleaning { return L("Temizleniyor", "Cleaning") }
        if model.isScanning { return L("Taranıyor", "Scanning") }
        return model.lastFreedBytes == nil ? L("Hazır", "Ready") : L("Tamamlandı", "Done")
    }

    private var subtitle: String {
        if let freed = model.lastFreedBytes {
            return L("\(Format.bytes(freed)) boşaltıldı · Seçili: \(Format.bytes(model.selectedBytes))", "\(Format.bytes(freed)) freed · Selected: \(Format.bytes(model.selectedBytes))")
        }
        return L("Temizlenebilir (seçili): \(Format.bytes(model.selectedBytes))", "Cleanable (selected): \(Format.bytes(model.selectedBytes))")
    }
}
