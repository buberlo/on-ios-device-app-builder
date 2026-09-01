import SwiftUI

@MainActor
struct AppRootView: View {
    @Bindable var store: PhoneBuilderStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                ProjectsView(store: store)
                    .navigationDestination(for: UUID.self) { projectID in
                        ProjectDetailView(store: store, projectID: projectID)
                    }
            }
            .tabItem {
                Label(BuilderAppTab.projects.title, systemImage: BuilderAppTab.projects.systemImage)
            }
            .tag(BuilderAppTab.projects)
            .accessibilityIdentifier("tab.projects")

            NavigationStack {
                ActivityView(store: store)
            }
            .tabItem {
                Label(BuilderAppTab.activity.title, systemImage: BuilderAppTab.activity.systemImage)
            }
            .tag(BuilderAppTab.activity)
            .accessibilityIdentifier("tab.activity")

            NavigationStack {
                SetupView(store: store)
            }
            .tabItem {
                Label(BuilderAppTab.setup.title, systemImage: BuilderAppTab.setup.systemImage)
            }
            .tag(BuilderAppTab.setup)
            .accessibilityIdentifier("tab.setup")
        }
        .tint(.indigo)
        .sheet(item: $store.presentedSheet) { sheet in
            switch sheet {
            case .createProject:
                CreateProjectSheet(store: store)
            }
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

#Preview("App") {
    AppRootView(store: .preview())
}
