import SwiftUI

@MainActor
struct ActivityView: View {
    let store: PhoneBuilderStore

    var body: some View {
        Group {
            if store.activity.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("Build and installation progress from your Mac appears here.")
                )
            } else {
                List {
                    Section {
                        ForEach(store.activity.reversed()) { event in
                            ActivityEventRow(event: event, projectName: projectName(for: event))
                        }
                    } header: {
                        Text("Latest first")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            if store.projects.contains(where: { $0.runState.isRunning }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel active run", systemImage: "stop.fill", role: .destructive) {
                        store.cancelActiveRun()
                    }
                    .accessibilityIdentifier("activity.cancel")
                }
            }
        }
    }

    private func projectName(for event: AppBuildEvent) -> String? {
        guard let projectID = event.projectID else { return nil }
        return store.project(id: projectID)?.name
    }
}

private struct ActivityEventRow: View {
    let event: AppBuildEvent
    let projectName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.title3)
                .foregroundStyle(event.kind.color)
                .frame(width: 30, height: 30)
                .background(event.kind.color.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let projectName {
                    Text(projectName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.indigo)
                }

                Text(event.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let progress = event.progress {
                    ProgressView(value: progress)
                        .tint(event.kind.color)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity.event.\(event.kind.rawValue)")
    }
}

#Preview("Activity") {
    NavigationStack {
        ActivityView(store: .preview())
    }
}
