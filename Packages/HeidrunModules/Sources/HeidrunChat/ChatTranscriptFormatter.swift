import Foundation

/// Pure plain-text formatter that turns chat lines into a transcript for
/// export (drag-out / copy). System lines render as-is, action lines get
/// a leading "* ", normal lines as "sender: body". One line per entry.
enum ChatTranscriptFormatter {
    static func format(_ lines: [ChatViewModel.Line]) -> String {
        lines.map { line in
            if line.isSystem {
                return line.body
            }
            if line.isAction {
                return "* \(line.body)"
            }
            if let sender = line.sender, !sender.isEmpty {
                return "\(sender): \(line.body)"
            }
            return line.body
        }
        .joined(separator: "\n")
    }
}
