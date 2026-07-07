import SwiftUI

/// Drag to reorder Today's modules; toggle optional ones on/off.
struct ModulesEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.modules.orderedKeys, id: \.self) { key in
                        HStack {
                            Text(store.modules.label(key))
                                .font(.system(size: 16))
                                .foregroundStyle(store.modules.enabled(key) ? Theme.ink : Theme.tertiaryInk)
                            Spacer()
                            if ModulePrefs.coreKeys.contains(key) {
                                Text("core").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.tertiaryInk)
                            } else {
                                Toggle("", isOn: Binding(
                                    get: { store.modules.enabled(key) },
                                    set: { v in store.updateModules { $0.setEnabled(key, v) } }))
                                    .labelsHidden().tint(Theme.sage)
                            }
                        }
                    }
                    .onMove { offs, dest in store.moveModule(from: offs, to: dest) }
                } footer: {
                    Text("Drag the handle to reorder. Turn modules off to hide them on Today. Non-negotiables and Daily score always stay.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(WarmBackground())
            .navigationTitle("Reorder modules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .tint(Theme.accentDark)
    }
}
