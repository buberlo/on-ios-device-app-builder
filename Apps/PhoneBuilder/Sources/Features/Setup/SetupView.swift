import SwiftUI

@MainActor
struct SetupView: View {
    let store: PhoneBuilderStore

    var body: some View {
        List {
            connectionSection
            requirementsSection
            privacySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Setup")
        .refreshable {
            store.refreshSetup()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    store.refreshSetup()
                }
                .accessibilityIdentifier("setup.refresh")
            }
        }
    }

    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: store.setup.connectionState == .connected ? "macbook.and.iphone" : "wifi")
                        .font(.largeTitle)
                        .foregroundStyle(store.setup.connectionState == .connected ? .green : .indigo)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.setup.connectionState.title)
                            .font(.headline)
                        Text(connectionDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.setup.connectionState == .connected {
                    HStack {
                        Label("Encrypted local connection", systemImage: "lock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect") {
                            store.disconnect()
                        }
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("setup.disconnect")
                    }
                }
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setup.connection")

            if store.setup.connectionState != .connected {
                if store.setup.discoveredMacs.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Open Builder Host on your Mac…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("setup.searching")
                } else {
                    ForEach(store.setup.discoveredMacs) { mac in
                        MacRow(mac: mac, isConnecting: store.setup.connectionState == .connecting) {
                            store.connect(to: mac)
                        }
                    }
                }
            }
        } header: {
            Text("Mac connection")
        } footer: {
            Text("The iPhone sends typed build requests only. Source code, Xcode, and signing stay on your Mac.")
        }
    }

    private var requirementsSection: some View {
        Section {
            if store.setup.checks.isEmpty {
                HStack {
                    ProgressView()
                    Text("Connect to check your Mac")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.setup.checks) { check in
                    RequirementRow(check: check)
                }
            }

            if let deviceName = store.setup.connectedDeviceName {
                LabeledContent("Install target") {
                    Label(deviceName, systemImage: "iphone")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("setup.install-target")
            }
        } header: {
            HStack {
                Text("Mac requirements")
                Spacer()
                if !store.setup.checks.isEmpty {
                    Text("\(store.setup.readyCount)/\(store.setup.checks.count) ready")
                }
            }
        } footer: {
            if store.setup.isReadyToBuild {
                Label("Ready to create and install apps", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Fix unavailable items on the Mac, then refresh this screen.")
            }
        }
    }

    private var privacySection: some View {
        Section("Security") {
            Label("Encrypted peer-to-peer session", systemImage: "lock.shield")
            Label("No remote shell exposed", systemImage: "terminal.fill")
            Label("Build actions are allow-listed", systemImage: "checklist.checked")
        }
        .foregroundStyle(.secondary)
    }

    private var connectionDetail: String {
        if let mac = store.setup.connectedMac {
            return mac.name
        }
        return switch store.setup.connectionState {
        case .discovering: "Searching on your local network"
        case .disconnected: "Choose a nearby Mac below"
        case .connecting: "Waiting for the secure session"
        case .connected: "Secure session active"
        }
    }
}

private struct MacRow: View {
    let mac: AppMac
    let isConnecting: Bool
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "macbook")
                .font(.title2)
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                    .font(.headline)
                Text(mac.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isConnecting ? "Connecting…" : "Connect", action: connect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isConnecting)
                .accessibilityIdentifier("setup.connect")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RequirementRow: View {
    let check: AppSetupCheck

    var body: some View {
        HStack(spacing: 12) {
            RequirementStateIcon(state: check.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.medium))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("setup.check.\(check.id)")
    }
}

#Preview("Setup") {
    NavigationStack {
        SetupView(store: .preview())
    }
}
