import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

/// News surface that adapts to the server's capabilities.
///
/// On appear we ask the client for its `connectionInfo`, derive a
/// `NewsCapability`, and show exactly one UI:
///   * `.plain` — single bulletin-board view (Hotline < 1.5 + WC servers).
///   * `.threaded` — hierarchical browser (Hotline 1.5+).
///
/// We only fetch the flavour the server actually advertises, matching the
/// rule "load only the one the server runs".
public struct NewsView: View {
    @State private var plain: PlainNewsViewModel
    @State private var threaded: ThreadedNewsViewModel
    @State private var capability: NewsCapability?

    private let resolveCapability: @Sendable () async -> NewsCapability
    private let ownNickname: String

    /// Production initialiser: derives the capability from the live client.
    public init(client: any HotlineClient, ownNickname: String = "") {
        self._plain    = State(initialValue: PlainNewsViewModel(client: client))
        self._threaded = State(initialValue: ThreadedNewsViewModel(client: client))
        self.ownNickname = ownNickname
        self.resolveCapability = {
            NewsCapability(serverVersion: await client.connectionInfo.serverVersion)
        }
    }

    /// Test / preview initialiser: callers inject ready-made view-models and
    /// an explicit capability so no live client is needed.
    public init(
        plain: PlainNewsViewModel,
        threaded: ThreadedNewsViewModel,
        capability: NewsCapability,
        ownNickname: String = ""
    ) {
        self._plain      = State(initialValue: plain)
        self._threaded   = State(initialValue: threaded)
        self._capability = State(initialValue: capability)
        self.ownNickname = ownNickname
        self.resolveCapability = { capability }
    }

    /// Hosted initialiser: inject view-models persisted on the connection
    /// (so the composer draft + browse state survive feature switches).
    /// Pass a pre-resolved `capability` (hoisted on the connection) so the
    /// first frame renders real content and the sidebar feature-switch
    /// crossfade applies; when `nil` we resolve it from the live client in
    /// `bootstrap()` as before (brief pre-`start()` window only).
    public init(
        plain: PlainNewsViewModel,
        threaded: ThreadedNewsViewModel,
        client: any HotlineClient,
        capability: NewsCapability? = nil,
        ownNickname: String = ""
    ) {
        self._plain      = State(initialValue: plain)
        self._threaded   = State(initialValue: threaded)
        self._capability = State(initialValue: capability)
        self.ownNickname = ownNickname
        self.resolveCapability = {
            NewsCapability(serverVersion: await client.connectionInfo.serverVersion)
        }
    }

    public var body: some View {
        Group {
            switch capability {
            case .none:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .plain:
                PlainNewsScreen(viewModel: plain)
                    .padding(.bottom, .xlarge)
            case .threaded:
                ThreadedNewsScreen(viewModel: threaded, ownNickname: ownNickname)
                    .padding(.bottom, .xlarge)
            }
        }
        .task { await bootstrap() }
    }

    /// Detect capability, then autofetch only the flavour the server runs.
    /// Plain-news `.newsPosted` observation is owned at connection scope, so
    /// `start()` here is an idempotent no-op for the hoisted VM (only the
    /// standalone `NewsView(client:)` path does work). Threaded servers don't push.
    private func bootstrap() async {
        if capability == nil {
            capability = await resolveCapability()
        }
        switch capability {
        case .plain:
            plain.start()
            await plain.refresh()
        case .threaded:
            await threaded.refresh()
        case .none:
            break
        }
    }
}

// MARK: - Plain news

private struct PlainNewsScreen: View {
    @Bindable var viewModel: PlainNewsViewModel

    private var posts: [String] {
        viewModel.feed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            feed
            Divider()
            composer
                .padding(.top, .small)
                .padding(.bottom, .small)
        }
        .padding(.bottom, .small)
        .frame(alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: Spacing.xxsmall.rawValue) {
            Image(systemName: "newspaper")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("News", bundle: .module)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(viewModel.isLoading)
            .help(String(localized: "Reload news feed", bundle: .module))
        }
        .filledHeaderBox()
        .padding(.horizontal, .xsmall)
    }

    @ViewBuilder
    private var feed: some View {
        if viewModel.isLoading && posts.isEmpty {
            ProgressView(String(localized: "Loading news…", bundle: .module))
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if posts.isEmpty {
            ContentUnavailableView(
                String(localized: "No News Yet", bundle: .module),
                systemImage: "newspaper",
                description: Text("Posts will appear here when someone shares an update.", bundle: .module)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SelectableTranscript(
                lines: NewsPostsTranscriptProjection.lines(from: posts),
                scrollAnchor: viewModel.transcriptScroll
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
            HStack(alignment: .top, spacing: Spacing.xsmall.rawValue) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.draft)
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 160)
                        .scrollContentBackground(.hidden)

                    if viewModel.draft.isEmpty {
                        Text("Share an update with the server…", bundle: .module)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            // Align to the TextEditor's text origin (NSTextView
                            // line-fragment padding ≈ 5pt left, flush top) so the
                            // placeholder sits exactly where the cursor appears.
                            .padding(.leading, .xxsmall)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.xxsmall)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous)
                        .stroke(.separator, lineWidth: 0.5)
                )
                Spacer()
                Button {
                    Task { await viewModel.postDraft() }
                } label: {
                    Label(String(localized: "Post", bundle: .module), systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, .small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isDraftEmpty || !viewModel.permits(.postNews))
                .help(viewModel.permits(.postNews)
                    ? String(localized: "Post draft (⌘↩)", bundle: .module)
                    : String(localized: "Your account isn't allowed to post news", bundle: .module))
            }
            // Errors surface through the scene-root ErrorPresenter.
        }
        .padding(.horizontal, .small)
    }

    private var isDraftEmpty: Bool {
        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Threaded news

private struct ThreadedNewsScreen: View {
    @Bindable var viewModel: ThreadedNewsViewModel
    let ownNickname: String
    @State private var composing = false
    @State private var creatingBundle = false
    @State private var deleteTarget: NewsBundle?
    @State private var editThreadTarget: NewsThread?
    @State private var deleteThreadTarget: NewsThread?
    @State private var replyTarget: NewsThread?

    private var actions: NewsThreadActions {
        NewsThreadActions(
            viewModel: viewModel,
            ownNickname: ownNickname,
            onEdit: { thread in editThreadTarget = thread },
            onConfirmDelete: { thread in deleteThreadTarget = thread },
            onReply: { thread in replyTarget = thread }
        )
    }

    /// The currently-selected thread (row), or nil. Toolbar + menu act
    /// on this — not on the loaded body — so empty-body/top-level posts
    /// are actionable.
    private var selectedThread: NewsThread? { viewModel.selectedThread }

    private var canEditSelected: Bool {
        guard let thread = selectedThread else { return false }
        return actions.canEdit(thread)
    }

    private func copySelectedPost() {
        guard let thread = selectedThread else { return }
        actions.copyPost(thread)
    }

    private func copySelectedThread() {
        guard let thread = selectedThread else { return }
        actions.copyThread(thread)
    }

    private func editSelected() {
        // Prefer the fully-loaded thread (TX 400 body) over the list
        // metadata (TX 371, no body) so the sheet's body field isn't
        // empty — saving an empty body would wipe the original post.
        guard let thread = viewModel.editableSelectedThread else { return }
        editThreadTarget = thread
    }

    private func deleteSelected() {
        guard let thread = selectedThread else { return }
        deleteThreadTarget = thread
    }

    private func replySelected() {
        guard let thread = selectedThread else { return }
        replyTarget = thread
    }

    private func copySelectedBundleContents() {
        guard let bundle = viewModel.selectedBundle else { return }
        Task { await actions.copyContents(bundle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumb
            Divider()
            HSplitView {
                leftPane
                    .frame(minWidth: 200, idealWidth: 220)
                    .background(SplitViewAutosaver(name: "news.threaded.bundles"))
                rightPane
                    .frame(minWidth: 320)
            }
            .padding(.top, .xsmall)
            // Errors surface through the scene-root ErrorPresenter.
        }
        .frame(alignment: .topLeading)
        .sheet(isPresented: $composing) {
            NewPostSheet { title, body in
                await viewModel.post(title: title, body: body)
            }
        }
        .sheet(item: $replyTarget) { thread in
            NewPostSheet(
                title: String(localized: "Reply", bundle: .module),
                initialTitle: NewsThreadActions.replyTitle(
                    forParent: thread.elements.first?.title ?? ""
                )
            ) { title, body in
                await viewModel.post(
                    parentThreadID: thread.threadID,
                    title: title,
                    body: body
                )
            }
        }
        .sheet(isPresented: $creatingBundle) {
            CreateBundleSheet { name, isCategory in
                await viewModel.createBundle(named: name, isCategory: isCategory)
            }
        }
        .alert(
            String(localized: "Delete this bundle?", bundle: .module),
            isPresented: deleteBinding,
            presenting: deleteTarget
        ) { bundle in
            Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                Task { await viewModel.deleteBundle(bundle) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { bundle in
            Text(
                bundle.kind == .category
                    ? String(localized: "“\(bundle.title)” and every thread inside it will be removed from the server. This can't be undone.", bundle: .module)
                    : String(localized: "“\(bundle.title)” and everything inside it will be removed from the server. This can't be undone.", bundle: .module)
            )
        }
        .sheet(item: $editThreadTarget) { thread in
            EditPostSheet(thread: thread) { newTitle, newBody in
                await viewModel.editThread(
                    threadID: thread.threadID,
                    newTitle: newTitle,
                    newBody: newBody
                )
            }
        }
        .confirmationDialog(
            String(localized: "Delete this post?", bundle: .module),
            isPresented: Binding(
                get: { deleteThreadTarget != nil },
                set: { if !$0 { deleteThreadTarget = nil } }
            ),
            presenting: deleteThreadTarget
        ) { thread in
            Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                Task {
                    await viewModel.deleteThread(
                        threadID: thread.threadID,
                        cascade: false
                    )
                }
                deleteThreadTarget = nil
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { deleteThreadTarget = nil }
        } message: { _ in
            Text("Any replies will remain visible as orphan posts.", bundle: .module)
        }
        // Publish selection + actions so the macOS "News" menu drives the
        // same handlers as the toolbar. Present only while this threaded
        // view is on screen, so the menu disables when focus leaves.
        .focusedValue(\.newsActionContext, NewsActionContext(
            hasSelection: selectedThread != nil,
            canEdit: canEditSelected,
            copyPost: { copySelectedPost() },
            copyThread: { copySelectedThread() },
            reply: { replySelected() },
            edit: { editSelected() },
            delete: { deleteSelected() },
            hasSelectedBundle: viewModel.selectedBundle != nil,
            copyBundleContents: { copySelectedBundleContents() }
        ))
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    // MARK: Breadcrumb / actions

    private var breadcrumb: some View {
        HStack(alignment: .center, spacing: Spacing.xxsmall.rawValue) {
            Image(systemName: "house")
                .resizable()
                .scaledToFit()
                .font(.subheadline)
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
            Button {
                Task { await viewModel.navigate(toDepth: 0) }
            } label: {
                Text("News", bundle: .module)
                    .heidrunBody()
            }
            .buttonStyle(.plain)
            .controlSize(.regular)
            .foregroundStyle(viewModel.currentPath.isRoot ? .primary : .secondary)
            .disabled(viewModel.currentPath.isRoot)

            ForEach(Array(viewModel.currentPath.components.enumerated()), id: \.offset) { index, component in
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .fontWeight(.light)
                    .imageScale(.small)
                let isCurrent = index == viewModel.currentPath.components.count - 1
                Button {
                    Task { await viewModel.navigate(toDepth: index + 1) }
                } label: {
                    Text(component)
                        .heidrunBody()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .disabled(isCurrent)
            }

            Spacer()

            ActionButton(
                title: "Copy Post",
                systemImage: "doc.on.doc",
                isEnabled: selectedThread != nil,
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                copySelectedPost()
            }

            ActionButton(
                title: "Copy Thread",
                systemImage: "doc.on.doc.fill",
                isEnabled: selectedThread != nil,
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                copySelectedThread()
            }

            ActionButton(
                title: "Edit Post…",
                systemImage: "pencil",
                isEnabled: canEditSelected && viewModel.permits(.postNews),
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                editSelected()
            }

            ActionButton(
                title: "Delete Post…",
                systemImage: "trash",
                isEnabled: selectedThread != nil && viewModel.permits(.deleteArticles),
                role: .destructive,
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                deleteSelected()
            }

            Divider().frame(height: 16)

            ActionButton(
                title: "Copy Contents",
                systemImage: "doc.on.clipboard",
                isEnabled: viewModel.selectedBundle != nil && !viewModel.isGatheringCopy,
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                copySelectedBundleContents()
            }

            ActionButton(
                title: "New Bundle or Category…",
                systemImage: "plus",
                isEnabled: viewModel.permits(.createNewsBundles) || viewModel.permits(.createCategories),
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                creatingBundle = true
            }

            if viewModel.selectedCategoryPath != nil {
                ActionButton(
                    title: "New Thread…",
                    systemImage: "square.and.pencil",
                    isEnabled: viewModel.permits(.postNews),
                    size: .small,
                    fontWeight: .light,
                    bundle: .module
                ) {
                    composing = true
                }
            }

            ActionButton(
                title: "Reload",
                systemImage: "arrow.clockwise",
                isEnabled: !viewModel.isLoading,
                size: .small,
                fontWeight: .light,
                bundle: .module
            ) {
                Task { await viewModel.refresh() }
            }
        }
        .filledHeaderBox()
        .padding(.horizontal, .xsmall)
    }

    // MARK: Left pane — folders + categories

    @ViewBuilder
    private var leftPane: some View {
        if viewModel.isLoadingBundles && viewModel.bundles.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.bundles.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "Empty Folder", bundle: .module), systemImage: "folder")
            } description: {
                Text("Nothing here yet.", bundle: .module)
            } actions: {
                Button(String(localized: "Create…", bundle: .module)) { creatingBundle = true }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            BundleTableView(
                bundles: viewModel.bundles,
                selectedBundleID: viewModel.selectedBundleID,
                actions: bundleListActions
            )
        }
    }

    private var bundleListActions: BundleListActions {
        let actions = self.actions
        return BundleListActions(
            navigate: { bundle in
                Task {
                    if bundle.kind == .bundle {
                        await viewModel.descend(into: bundle)
                    } else {
                        await viewModel.select(bundle)
                    }
                }
            },
            menuItems: { bundle in
                var items: [ThreadMenuItem] = []
                if bundle.kind == .bundle {
                    items.append(.normal(String(localized: "Open", bundle: .module)) {
                        Task { await viewModel.descend(into: bundle) }
                    })
                }
                items.append(.normal(String(localized: "Refresh", bundle: .module)) {
                    Task { await viewModel.refresh() }
                })
                items.append(.normal(String(localized: "Copy Contents", bundle: .module)) {
                    Task { await actions.copyContents(bundle) }
                })
                if viewModel.permits(bundle.kind == .bundle ? .deleteNewsBundles : .deleteCategories) {
                    items.append(.separator)
                    items.append(.destructive(String(localized: "Delete…", bundle: .module)) {
                        deleteTarget = bundle
                    })
                }
                return items
            }
        )
    }

    // MARK: Right pane — thread tree + body

    private var rightPane: some View {
        // AppKit-backed split — see `PersistentVSplit` for why
        // SwiftUI's `VSplitView` couldn't hold the divider here.
        PersistentVSplit(
            autosaveName: "Heidrun.news.threaded.body",
            topMinHeight: 140,
            bottomMinHeight: 120,
            defaultTopHeight: 220
        ) {
            threadListPane
        } bottom: {
            // Own view so body-load mutations invalidate only this subtree,
            // not `ThreadedNewsScreen.body` (which would recreate
            // `ThreadOutlineView` + fire a redundant `updateNSView` per fetch).
            ThreadBodyPane(viewModel: viewModel, replyTarget: $replyTarget)
        }
    }

    /// The highlighted bundle on the left, if it's a folder rather than
    /// a category. Used to nudge the user toward double-clicking when
    /// they single-tap a folder.
    private var selectedFolder: NewsBundle? {
        guard let id = viewModel.selectedBundleID, id.kind == .bundle else { return nil }
        return viewModel.bundles.first(where: { $0.id == id })
    }

    @ViewBuilder
    private var threadListPane: some View {
        if viewModel.selectedCategoryPath == nil {
            ContentUnavailableView(
                selectedFolder == nil
                    ? String(localized: "No Category Selected", bundle: .module)
                    : String(localized: "Folder Selected", bundle: .module),
                systemImage: "tray",
                description: Text(
                    selectedFolder == nil
                        ? String(localized: "Pick a category on the left to see its threads.", bundle: .module)
                        : String(localized: "Double-click \u{201C}\(selectedFolder?.title ?? "")\u{201D} to open it, or pick a category.", bundle: .module)
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoadingThreads && viewModel.threads.isEmpty {
            ProgressView(String(localized: "Loading posts…", bundle: .module))
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.threads.isEmpty {
            ContentUnavailableView(
                String(localized: "No Posts Yet", bundle: .module),
                systemImage: "tray",
                description: Text("This category is empty. Use the pencil button above to start a thread.", bundle: .module)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            threadTreeList
        }
    }

    private var threadTreeList: some View {
        ThreadOutlineView(
            threads: viewModel.threads,
            selectedThreadID: viewModel.selectedThreadID,
            actions: outlineActions
        )
    }

    private var outlineActions: ThreadOutlineActions {
        // Capture `actions` once per render so the closures see the same
        // NewsThreadActions the toolbar/menu builders use.
        let actions = self.actions
        return ThreadOutlineActions(
            open: { thread in
                Task { await viewModel.openThread(thread) }
            },
            menuItems: { thread in
                var items: [ThreadMenuItem] = []
                if viewModel.permits(.postNews) {
                    items.append(.normal(String(localized: "Reply…", bundle: .module)) {
                        actions.onReply(thread)
                    })
                }
                if actions.canEdit(thread), viewModel.permits(.postNews) {
                    items.append(.normal(String(localized: "Edit…", bundle: .module)) {
                        actions.onEdit(thread)
                    })
                }
                if viewModel.permits(.deleteArticles) {
                    items.append(.destructive(String(localized: "Delete…", bundle: .module)) {
                        actions.onConfirmDelete(thread)
                    })
                }
                if !items.isEmpty {
                    items.append(.separator)
                }
                items.append(.normal(String(localized: "Copy Post", bundle: .module)) {
                    actions.copyPost(thread)
                })
                items.append(.normal(String(localized: "Copy Thread", bundle: .module)) {
                    actions.copyThread(thread)
                })
                return items
            },
            clipboardText: { thread in
                NewsClipboardFormatter.formatPost(thread)
            },
            clipboardTitle: { thread in
                thread.elements.first?.title ?? "News Post"
            }
        )
    }
}

/// The read pane for the selected post's body. Split out of
/// `ThreadedNewsScreen` so the body-load lifecycle (`isLoadingBody`,
/// `loadedThread`) only invalidates this subtree — keeping body fetches
/// from recreating the sibling `ThreadOutlineView`.
private struct ThreadBodyPane: View {
    let viewModel: ThreadedNewsViewModel
    @Binding var replyTarget: NewsThread?

    var body: some View {
        if viewModel.isLoadingBody {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let thread = viewModel.loadedThread, let element = thread.elements.first {
            ScrollView {
                // `Spacing.xsmall` (8pt) between the header row, the
                // hairline divider, and the body — so the divider does
                // the visual-separation work and the gap on each side
                // is breathing room, not a full margin.
                VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
                    HStack(spacing: Spacing.xsmall.rawValue) {
                        if let author = element.author.nonEmpty {
                            Label(author, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        if let display = thread.postDate.displayableAbsolute {
                            Text(display)
                        }
                        Spacer()
                        Button {
                            replyTarget = thread
                        } label: {
                            Label(String(localized: "Reply…", bundle: .module), systemImage: "arrowshape.turn.up.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .heidrunCaption()
                    .foregroundStyle(.secondary)

                    Divider()

                    if let body = element.body.nonEmpty {
                        Text(linkifyAttributed(body))
                            .heidrunBody()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.openURL, OpenURLAction { url in
                                // hotline/heidrun → in-app dispatch (no extra
                                // empty window); everything else (http(s))
                                // falls to the system default.
                                HotlineLinkClick.post(url) ? .handled : .systemAction
                            })
                    } else {
                        Text("(empty)", bundle: .module)
                            .heidrunBody()
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                String(localized: "No Thread Selected", bundle: .module),
                systemImage: "doc.text",
                description: Text("Pick a thread above to read its body here.", bundle: .module)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Build an `AttributedString` with `.link` runs on hotline/heidrun/http(s)
    /// URLs so `Text` clicks dispatch through `.onOpenURL` → connection. The
    /// threaded-news-body counterpart to SelectableTranscript.
    private func linkifyAttributed(_ body: String) -> AttributedString {
        var attributed = AttributedString(body)
        for link in HotlineLinkDetector.scan(body) {
            let nsRange = NSRange(link.range, in: body)
            guard let attributedRange = Range(nsRange, in: attributed) else { continue }
            attributed[attributedRange].link = link.url
        }
        return attributed
    }
}
