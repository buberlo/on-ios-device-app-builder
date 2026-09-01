import AppKit
import BuilderCore
import SwiftUI

struct HostMenuView: View {
    let store: HostStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionSection
                    setupSection
                    projectsSection
                    activitySection
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 390, height: 620)
        .task { await store.start() }
        .accessibilityIdentifier("builderHost.menu")
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(connectionColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "hammer.fill")
                    .foregroundStyle(connectionColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Builder Host")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                    Text(store.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh Mac setup")
            .accessibilityLabel("Refresh setup")
            .accessibilityIdentifier("builderHost.refresh")
        }
        .padding(16)
    }

    private var connectionSection: some View {
        HostSection(title: "Nearby connection", symbol: "iphone.and.arrow.forward") {
            if store.nearbyHost.connectedPeers.isEmpty {
                Label("Waiting for Phone Builder on the local network", systemImage: "wifi")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.nearbyHost.connectedPeers) { peer in
                    HStack {
                        Image(systemName: "iphone.gen3")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.displayName)
                                .font(.callout.weight(.medium))
                            Text("Encrypted session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var setupSection: some View {
        HostSection(title: "Mac setup", symbol: "checklist") {
            if store.checks.isEmpty {
                ProgressView("Checking prerequisites…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.checks) { check in
                    SetupCheckRow(check: check)
                }
            }
        }
    }

    private var projectsSection: some View {
        HostSection(title: "Recent projects", symbol: "square.stack.3d.up") {
            if store.projects.isEmpty {
                Text("Projects created on the iPhone will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.projects.prefix(5)) { project in
                    ProjectRow(project: project)
                }
            }
        }
    }

    private var activitySection: some View {
        HostSection(title: "Activity", symbol: "waveform.path.ecg") {
            if store.activities.isEmpty {
                Text("No requests yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.activities.prefix(6)) { activity in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: activity.symbol)
                            .foregroundStyle(activity.color)
                            .frame(width: 16)
                        Text(activity.message)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(activity.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Projects", systemImage: "folder") {
                store.openProjectsFolder()
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") {
                store.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var connectionColor: Color {
        switch store.nearbyHost.connectionState {
        case .connected: .green
        case .failed: .red
        case .connecting: .orange
        case .idle, .disconnected: .secondary
        case .advertising, .browsing: .blue
        }
    }
}

private struct HostSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SetupCheckRow: View {
    let check: HostCheckResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.symbol)
                .foregroundStyle(check.status.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.kind.title)
                    .font(.callout.weight(.medium))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectRow: View {
    let project: HostProjectRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.callout.weight(.medium))
                Text(project.bundleIdentifier)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(project.status.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(project.status.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(project.status.color.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

private extension HostCheckStatus {
    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .warning: .orange
        case .unavailable: .red
        }
    }
}

private extension HostProjectStatus {
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .succeeded: .green
        case .failed, .cancelled: .red
        case .planning, .generating, .building, .installing: .blue
        case .idle: .secondary
        }
    }
}

private extension HostActivity {
    var symbol: String {
        switch kind {
        case .connection: "wifi"
        case .request: "arrow.down.circle"
        case .plan: "text.bubble"
        case .build: "hammer"
        case .install: "iphone.and.arrow.forward"
        case .success: "checkmark.circle"
        case .failure: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch kind {
        case .success: .green
        case .failure: .red
        case .install, .build: .blue
        case .connection, .request, .plan: .secondary
        }
    }
}

#Preview {
    HostMenuView(store: .live())
}
