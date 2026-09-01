import SwiftUI

@main
struct PhoneBuilderApp: App {
    @State private var store = PhoneBuilderStore.makeForCurrentProcess()

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
                .task {
                    store.start()
                }
        }
    }
}
