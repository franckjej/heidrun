/*
import Combine
import SwiftUI
public extension View {
    func numericInput(
        _ text: Binding<String>,
        errorModel: ErrorViewModel
    ) -> some View {
        modifier(
            NumericTextModifier(text: text, errorModel: errorModel)
        )
    }
}

private struct NumericTextModifier: ViewModifier {
    
    private enum Constants {
        static let allNumbers = "0123456789,"
    }

    @Binding var text: String
    @ObservedObject var errorModel: ErrorViewModel

    let seperator: String = ","

    func body(content: Content) -> some View {
        content
            .onReceive(Just(text)) { newText in
                var numbers = Constants.allNumbers
                let value = newText.filter {
                    numbers.contains($0)
                }
                guard value != newText else { return }
                text = value
            }
    }
    private func hasSeparatorWithoutFollowingPart(_ text: String) -> Bool {
        text.components(separatedBy: seperator).count - 1 > 1
    }
}
*/
