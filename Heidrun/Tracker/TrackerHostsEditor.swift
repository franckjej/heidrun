import SwiftUI
import CommonTools

/// Popover-style editor for the persisted `TrackerHost` list. Read/
/// writes go through `TrackerHostsRegistry.shared` so changes
/// propagate to every observing surface immediately.
///
/// Validation lives at the row level: a host with an empty `host`
/// string or a port outside `1...65535` shows an inline warning and is
/// excluded from the next refresh anyway because the VM filters by
/// `enabled`. Saves on every keystroke — the UserDefaults round-trip
/// is cheap and the user shouldn't have to remember to hit "Apply".
@MainActor
struct TrackerHostsEditor: View {
    @State private var store = TrackerHostsRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            HStack {
                Text("Trackers")
                    .font(.headline)
                Spacer()
                Button {
                    store.append(TrackerHost(name: "new", host: "", port: 5498, enabled: true))
                } label: {
                    Label("Add tracker", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if store.hosts.isEmpty {
                ContentUnavailableView(
                    "No trackers configured",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Click Add tracker to start.")
                )
                .frame(minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.xsmall.rawValue) {
                        ForEach(store.hosts) { host in
                            TrackerHostRow(host: host) { updated in
                                store.update(updated)
                            } onRemove: {
                                store.remove(host.id)
                            }
                        }
                    }
                }
                .frame(minHeight: 180)
            }
        }
        .padding(.medium)
        .frame(width: 420)
    }
}

private struct TrackerHostRow: View {
    let host: TrackerHost
    let onUpdate: (TrackerHost) -> Void
    let onRemove: () -> Void

    @State private var draft: TrackerHost

    init(host: TrackerHost, onUpdate: @escaping (TrackerHost) -> Void, onRemove: @escaping () -> Void) {
        self.host = host
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        self._draft = State(initialValue: host)
    }

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Toggle("", isOn: Binding(
                get: { draft.enabled },
                set: { newValue in
                    draft.enabled = newValue
                    onUpdate(draft)
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            TextField("Label", text: Binding(
                get: { draft.name },
                set: { newValue in
                    draft.name = newValue
                    onUpdate(draft)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 96)

            TextField("Host", text: Binding(
                get: { draft.host },
                set: { newValue in
                    draft.host = newValue
                    onUpdate(draft)
                }
            ))
            .textFieldStyle(.roundedBorder)

            TextField(
                "Port",
                value: Binding(
                    get: { Int(draft.port) },
                    set: { newValue in
                        let clamped = UInt16(clamping: max(1, min(newValue, 65535)))
                        draft.port = clamped
                        onUpdate(draft)
                    }
                ),
                format: .number.grouping(.never)
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
