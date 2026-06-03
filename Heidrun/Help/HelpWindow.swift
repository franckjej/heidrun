import SwiftUI
import CommonTools

/// Standalone help window with a NavigationSplitView: topic list on
/// the left, rendered markdown on the right. Opened from the Help
/// menu (see `HelpCommands` and `HeidrunMainApp`).
struct HelpView: View {
    /// Table uses the row's `id` for selection bindings, so we track
    /// the selected ID (a string) and resolve back to `HelpTopic` for
    /// the detail pane. Defaults to the first topic so the help
    /// window opens with content visible.
    @State private var selectedTopicID: HelpTopic.ID? = HelpTopic.connecting.id

    private var selectedTopic: HelpTopic? {
        guard let selectedTopicID else { return nil }
        return HelpTopic(rawValue: selectedTopicID)
    }

    var body: some View {
        NavigationSplitView {
            // macOS SwiftUI List selection is unreliable in sidebar
            // contexts; Table behaves predictably for single-click
            // selection (same fix we landed in UserListInspector).
            // Single-column Table with the header hidden reads as a
            // sidebar list to the user.
            Table(HelpTopic.allCases, selection: $selectedTopicID) {
                TableColumn("Topic") { topic in
                    Label(topic.displayName, systemImage: topic.systemImage)
                        .padding(.vertical, .xxsmall)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .tableColumnHeaders(.hidden)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            if let topic = selectedTopic {
                HelpDocumentView(topic: topic)
                    .navigationTitle(topic.displayName)
            } else {
                ContentUnavailableView(
                    "Pick a topic",
                    systemImage: "questionmark.circle",
                    description: Text("Choose a topic on the left to see its help page.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
