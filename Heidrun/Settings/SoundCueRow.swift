import SwiftUI
import HeidrunUI

/// One cue in the Sounds tab: enable switch plus a preview button.
struct SoundCueRow: View {
    let cue: SoundCue
    @AppStorage private var isEnabled: Bool

    init(cue: SoundCue) {
        self.cue = cue
        _isEnabled = AppStorage(wrappedValue: true, SoundPlayer.defaultsKey(for: cue))
    }

    var body: some View {
        HStack {
            Toggle(title, isOn: $isEnabled)
            Spacer()
            Button("Play") { SoundPlayer.shared.preview(cue) }
        }
    }

    private var title: LocalizedStringKey {
        switch cue {
        case .login:
            "Connected"
        case .logout:
            "Disconnected"
        case .chatPost:
            "Chat message"
        case .doorbell:
            "Private chat invitation"
        case .news:
            "News posted"
        case .serverMessage:
            "Private message or broadcast"
        case .fileDone:
            "Transfer finished"
        }
    }
}
