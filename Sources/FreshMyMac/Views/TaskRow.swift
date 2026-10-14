import SwiftUI

struct TaskRow: View {
    let task: CleanupTask
    let isSelected: Bool
    let state: ScanState
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in toggle() })) {}
                .toggleStyle(.check)
                .accessibilityLabel(task.title)
            Plate(icon: task.icon, color: task.category.plate)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title).font(.system(size: 14, weight: .medium))
                    if task.requiresAdmin {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.mute)
                            .help(L("Yönetici şifresi gerektirir", "Requires an administrator password"))
                    }
                }
                Text(task.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mute)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            stateView
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    @ViewBuilder private var stateView: some View {
        switch state {
        case .idle, .notMeasurable:
            EmptyView()
        case .scanning:
            ProgressView().controlSize(.small)
        case let .measured(bytes, _):
            if bytes == 0 {
                Chip(text: L("Temiz", "Clean"), background: Theme.okSoft, foreground: Theme.onOk)
            } else {
                Text(Format.bytes(bytes)).font(Theme.mono(13))
            }
        case .noAccess:
            Button {
                SystemSettings.openFullDiskAccess()
            } label: {
                Label(L("Erişim yok", "No access"), systemImage: "exclamationmark.lock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.link)
            }
            .buttonStyle(.plain)
            .help(L("Tam Disk Erişimi ayarlarını açar", "Opens Full Disk Access settings"))
        }
    }
}
