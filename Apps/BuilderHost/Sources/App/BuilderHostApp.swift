import SwiftUI

@main
struct BuilderHostApp: App {
    @State private var store: HostStore

    init() {
        let store = HostStore.live()
        _store = State(initialValue: store)
        Task { @MainActor in
            await store.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            HostMenuView(store: store)
        } label: {
            Label("Builder Host", systemImage: store.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
