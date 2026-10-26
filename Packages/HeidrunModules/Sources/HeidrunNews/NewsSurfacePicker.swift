import SwiftUI

/// Board/Threaded switch on threaded servers.
struct NewsSurfacePicker: View {
    @Binding var selection: NewsSurface

    var body: some View {
        Picker(String(localized: "News view", bundle: .module), selection: $selection) {
            Text("Board", bundle: .module).tag(NewsSurface.board)
            Text("Threaded", bundle: .module).tag(NewsSurface.threaded)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help(String(localized: "Switch between the plain news board and threaded news", bundle: .module))
    }
}
