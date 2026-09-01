import SwiftUI

@MainActor
struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: PhoneBuilderStore

    @State private var name = ""
    @State private var bundleIdentifier = "dev.example."
    @State private var prompt = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case bundleIdentifier
        case prompt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("App identity") {
                    TextField("App name", text: $name)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("project.name")

                    TextField("Bundle identifier", text: $bundleIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .focused($focusedField, equals: .bundleIdentifier)
                        .accessibilityIdentifier("project.bundle")
                }

                Section("First prompt") {
                    TextField(
                        "What should the app do?",
                        text: $prompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .focused($focusedField, equals: .prompt)
                    .accessibilityIdentifier("project.prompt")

                    Text("You can refine the app in chat after creating it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.createProject(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                    .accessibilityIdentifier("project.create")
                }
            }
            .onAppear {
                focusedField = .name
            }
            .onChange(of: name) { _, newName in
                guard bundleIdentifier == "dev.example." || bundleIdentifier.hasPrefix("dev.example.") else {
                    return
                }
                bundleIdentifier = "dev.example.\(PhoneBuilderStore.bundleComponent(from: newName))"
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleIdentifier.split(separator: ".").count >= 3
            && !bundleIdentifier.contains(" ")
    }
}

#Preview {
    CreateProjectSheet(store: .preview())
}
