import SwiftUI

public struct ActionButton: View {
    public init(title: LocalizedStringKey, systemImage: String, isEnabled: Bool, role: ButtonRole? = nil, size: ControlSize? = .regular, fontWeight: Font.Weight? = .light, bundle: Bundle? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.role = role
        self.size = size
        self.action = action
        self.fontWeight = fontWeight
        self.bundle = bundle
    }

    let title: LocalizedStringKey
    // Bundle the `title` key is resolved against. Callers in SwiftPM feature
    // modules pass `.module` so the tooltip localizes from the module catalog;
    // nil keeps the default `Bundle.main` lookup.
    let bundle: Bundle?
    let systemImage: String
    let isEnabled: Bool
    let role: ButtonRole?
    let size: ControlSize?
    let fontWeight: Font.Weight?
    let action: () -> Void

    public var body: some View {
        Button(role: role, action: action) {
                // Constrain the icon to a fixed 16x16 area so SF Symbols of
                // different intrinsic widths (e.g. bubble.left.and.bubble.right
                // vs envelope) don't stretch the bordered button background.
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .fontWeight(fontWeight)
                .frame(width: sizeForControlSize(self.size ?? .regular), height: sizeForControlSize(self.size ?? .regular))
                .padding(.tiny)
        }
        .buttonStyle(.accessoryBarAction)
        .controlSize(size ?? .regular)
        .disabled(!isEnabled)
        .help(Text(title, bundle: bundle))
    }

    func sizeForControlSize(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini:
            return 11
        case .small:
            return 14
        default:
            return 16
        }
    }
}
