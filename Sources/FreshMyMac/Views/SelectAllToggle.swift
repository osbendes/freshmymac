import SwiftUI

/// Bir küme seçimini toplu yöneten onay kutusu. Hepsi seçiliyse ☑, hiçbiri seçili değilse ☐,
/// kısmen seçiliyse "–" gösterir. Tıklanınca hepsini seçer veya seçimi kaldırır.
struct SelectAllToggle<ID: Hashable>: View {
    var title: String = L("Tümünü seç", "Select all")
    let ids: [ID]
    @Binding var selection: Set<ID>

    var body: some View {
        Toggle(sources: ids.map(binding), isOn: \.self) {
            if !title.isEmpty { Text(title) }
        }
        .toggleStyle(.check)
        .accessibilityLabel(title.isEmpty ? L("Tümünü seç", "Select all") : title)
        .disabled(ids.isEmpty)
    }

    private func binding(for id: ID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { if $0 { selection.insert(id) } else { selection.remove(id) } }
        )
    }
}

/// Tek bir öğe için seçim kutusu bağlamı.
extension Binding {
    @MainActor static func membership<ID: Hashable & Sendable>(_ id: ID, in set: Binding<Set<ID>>) -> Binding<Bool> where Value == Bool {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { if $0 { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } }
        )
    }
}
