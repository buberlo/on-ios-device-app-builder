import SwiftUI

@MainActor
struct ProjectsView: View {
    let store: PhoneBuilderStore

    var body: some View {
        Group {
            if store.projects.isEmpty {
                ContentUnavailableView {
                    Label("No projects yet", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Describe your first iPhone app. Your Mac handles Xcode, signing, and installation.")
                } actions: {
                    Button("Create project", systemImage: "plus") {
                        store.presentedSheet = .createProject
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("projects.empty.create")
                }
            } else {
                List {
                    Section {
                        ConnectionBanner(
                            state: store.setup.connectionState,
                            hostName: store.setup.connectedMac?.name
                        )
                        .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }

                    Section("Your apps") {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectRow(project: project)
                            }
                            .accessibilityIdentifier("project.row.\(project.id.uuidString)")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    store.requestSnapshot()
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New project", systemImage: "plus") {
                    store.presentedSheet = .createProject
                }
                .accessibilityIdentifier("projects.add")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: AppProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 42, height: 42)
                .background(.indigo.opacity(0.1), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text(project.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            RunStatePill(state: project.runState)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Projects") {
    NavigationStack {
        ProjectsView(store: .preview())
    }
}
