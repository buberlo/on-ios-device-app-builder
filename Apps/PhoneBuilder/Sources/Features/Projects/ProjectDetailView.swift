import SwiftUI

@MainActor
struct ProjectDetailView: View {
    let store: PhoneBuilderStore
    let projectID: UUID

    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                conversation(project: project)
            } else {
                ContentUnavailableView(
                    "Project unavailable",
                    systemImage: "exclamationmark.folder",
                    description: Text("Refresh Projects after reconnecting to your Mac.")
                )
            }
        }
        .navigationTitle(store.project(id: projectID)?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Build", systemImage: "hammer") {
                    Task { await store.build(projectID: projectID) }
                }
                .disabled(store.project(id: projectID)?.runState.isRunning == true)
                .accessibilityIdentifier("project.build")

                Button("Install", systemImage: "iphone.and.arrow.forward") {
                    Task { await store.install(projectID: projectID) }
                }
                .disabled(store.project(id: projectID)?.runState.isRunning == true)
                .accessibilityIdentifier("project.install")
            }
        }
    }

    private func conversation(project: AppProject) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ProjectStatusHeader(project: project, eventCount: store.events(for: projectID).count)

                    if store.messages(for: projectID).isEmpty {
                        PromptSuggestions { suggestion in
                            draft = suggestion
                            isComposerFocused = true
                        }
                    } else {
                        ForEach(store.messages(for: projectID)) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if project.runState.isRunning {
                        BuildProgressCard(
                            state: project.runState,
                            latestEvent: store.events(for: projectID).last
                        )
                        .id("build-progress")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                ChatComposer(
                    text: $draft,
                    isFocused: $isComposerFocused,
                    isEnabled: !project.runState.isRunning
                ) {
                    sendDraft()
                }
            }
            .onChange(of: store.messages(for: projectID).count) { _, _ in
                guard let lastID = store.messages(for: projectID).last?.id else { return }
                withAnimation {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: project.runState) { _, newState in
                if newState.isRunning {
                    withAnimation {
                        proxy.scrollTo("build-progress", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            await store.sendPrompt(text, projectID: projectID)
        }
    }
}

private struct ProjectStatusHeader: View {
    let project: AppProject
    let eventCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("\(eventCount) build events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            RunStatePill(state: project.runState)
                .accessibilityIdentifier("project.status")
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

private struct PromptSuggestions: View {
    let select: (String) -> Void

    private let prompts = [
        "Create a clean SwiftUI home screen",
        "Add local persistence and sample data",
        "Improve accessibility and dark mode",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Describe the next change", systemImage: "sparkles")
                .font(.headline)

            ForEach(prompts, id: \.self) { prompt in
                Button(prompt) {
                    select(prompt)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

private struct ChatBubble: View {
    let message: AppChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(author, systemImage: authorSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(background, in: .rect(cornerRadius: 16))

            if message.role != .user {
                Spacer(minLength: 48)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.message.\(message.role.rawValue)")
    }

    private var author: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Builder"
        case .system: "System"
        }
    }

    private var authorSymbol: String {
        switch message.role {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "gearshape.fill"
        }
    }

    private var background: Color {
        switch message.role {
        case .user: .indigo.opacity(0.16)
        case .assistant: Color(uiColor: .secondarySystemGroupedBackground)
        case .system: .orange.opacity(0.12)
        }
    }
}

private struct BuildProgressCard: View {
    let state: AppRunState
    let latestEvent: AppBuildEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView()
                Text(state.title)
                    .font(.headline)
            }

            if let latestEvent {
                Text(latestEvent.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let progress = latestEvent.progress {
                    ProgressView(value: progress)
                        .tint(.indigo)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.indigo.opacity(0.1), in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("build.progress")
    }
}

private struct ChatComposer: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isEnabled: Bool
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Describe a change", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .accessibilityIdentifier("chat.input")

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chat.send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

#Preview("Project chat") {
    let store = PhoneBuilderStore.preview()
    NavigationStack {
        ProjectDetailView(store: store, projectID: store.projects[0].id)
    }
}
