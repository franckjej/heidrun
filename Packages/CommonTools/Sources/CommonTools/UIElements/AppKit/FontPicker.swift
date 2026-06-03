import SwiftUI
import Combine
import AppKit

public class FontPickerDelegate {
    var parent: FontPicker

    public init(_ parent: FontPicker) {
        self.parent = parent
    }

    @MainActor @objc
    func changeFont(_ id: Any) {
        parent.fontSelected()
    }
}

public struct FontPicker: View {
    public init(labelString: String, font: Binding<NSFont>, fontPickerDelegate: FontPickerDelegate? = nil) {
        self.labelString = labelString
        self._font = font
        self.fontPickerDelegate = fontPickerDelegate
    }

    let labelString: String

    @Binding var font: NSFont
    @State var fontPickerDelegate: FontPickerDelegate?

    public init(_ label: String, selection: Binding<NSFont>) {
        self.labelString = label
        self._font = selection
    }
    let fontManager = NSFontManager.shared
    let fontPanel = NSFontPanel.shared
    public var body: some View {
        HStack {
            Text(labelString)

            Button {
                if NSFontPanel.shared.isVisible {
                    NSFontPanel.shared.orderOut(nil)
                    return
                }

                self.fontPickerDelegate = FontPickerDelegate(self)
                fontManager.target = self.fontPickerDelegate
                fontPanel.setPanelFont(self.font, isMultiple: false)
                fontPanel.orderBack(nil)
            } label: {
               Text("…")
                    .font(.body)
                    .padding(.horizontal, .tiny)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    func fontSelected() {
        if NSFontPanel.shared.convert(self.font).pointSize > 32 {
            NSFontManager.shared.setSelectedFont(NSFont(descriptor: NSFontPanel.shared.convert(self.font).fontDescriptor, size: 24) ?? self.font, isMultiple: false)
            self.font = NSFontManager.shared.selectedFont ?? NSFontPanel.shared.convert(self.font)
        } else {
            self.font = NSFontPanel.shared.convert(self.font)
        }
    }
}

struct FontPicker_Previews: PreviewProvider {
    static var previews: some View {
        FontPicker("font", selection: .constant(NSFont.systemFont(ofSize: 24)))
    }
}
