import SwiftUI

struct ConnectionBanner: View {
    let state: AppConnectionState
    let hostName: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state == .connected ? "checkmark.circle.fill" : "wifi")
                .foregroundStyle(state == .connected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                if let hostName {
                    Text(hostName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection.banner")
    }
}
struct RunStatePill: View {
    let state: AppRunState

    var body: some View {
        Label(state.title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: .capsule)
            .accessibilityLabel("Status: \(state.title)")
    }

    private var color: Color {
        switch state {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        case .idle: .secondary
        default: .indigo
        }
    }

    private var symbol: String {
        switch state {
        case .succeeded: "checkmark"
        case .failed: "xmark"
        case .cancelled: "stop.fill"
        case .idle: "circle"
        default: "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
}

struct RequirementStateIcon: View {
    let state: AppCheckState

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        case .checking: "ellipsis.circle"
        }
    }

    private var color: Color {
        switch state {
        case .ready: .green
        case .warning: .orange
        case .unavailable: .red
        case .checking: .secondary
        }
    }

    private var label: String {
        switch state {
        case .ready: "Ready"
        case .warning: "Needs attention"
        case .unavailable: "Unavailable"
        case .checking: "Checking"
        }
    }
}

extension AppEventKind {
    var symbol: String {
        switch self {
        case .connection: "wifi"
        case .project: "plus.square"
        case .planning: "list.bullet.clipboard"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .build: "hammer.fill"
        case .install: "iphone.and.arrow.forward"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .error: .red
        case .install: .blue
        case .build, .code, .planning: .indigo
        case .connection, .project: .secondary
        }
    }
}
