import BuilderCore
import Foundation

struct HostDiagnosticsSnapshot: Equatable, Sendable {
    let checks: [HostCheckResult]
    let devices: [DeploymentDevice]
}

struct HostDiagnostics: Sendable {
    private let runner: AllowlistedCommandRunner
    private let toolLocator: ToolLocator
    private let fileManager: SendableFileManager

    init(
        runner: AllowlistedCommandRunner,
        toolLocator: ToolLocator = ToolLocator(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.toolLocator = toolLocator
        self.fileManager = SendableFileManager(fileManager)
    }

    func inspect() async -> HostDiagnosticsSnapshot {
        let xcodeResult = await inspectXcode()
        let signingResult = await inspectSigning()
        let tuistResult = await inspectTuist()
        let codexResult = await inspectCodex()
        let deviceResult = await inspectDevices(xcodeMajorVersion: Self.majorVersion(in: xcodeResult.detail))
        return HostDiagnosticsSnapshot(
            checks: [xcodeResult, signingResult, tuistResult, codexResult, deviceResult.check],
            devices: deviceResult.devices
        )
    }

    private func inspectXcode() async -> HostCheckResult {
        do {
            let output = try await runner.run(.xcodeVersion)
            let firstLine = output.text.split(separator: "\n").first.map(String.init) ?? "Xcode found"
            return HostCheckResult(
                kind: .xcode,
                status: output.succeeded ? .ready : .unavailable,
                detail: output.succeeded ? firstLine : summarized(output.text, fallback: "xcodebuild failed")
            )
        } catch {
            return HostCheckResult(kind: .xcode, status: .unavailable, detail: error.localizedDescription)
        }
    }

    private func inspectSigning() async -> HostCheckResult {
        do {
            let output = try await runner.run(.signingIdentities)
            let developmentIdentity = output.text
                .split(separator: "\n")
                .map(String.init)
                .first { $0.localizedCaseInsensitiveContains("Apple Development") }
            return HostCheckResult(
                kind: .signing,
                status: developmentIdentity == nil ? .unavailable : .ready,
                detail: developmentIdentity.map(cleanIdentity) ?? "No Apple Development identity found"
            )
        } catch {
            return HostCheckResult(kind: .signing, status: .unavailable, detail: error.localizedDescription)
        }
    }

    private func inspectTuist() async -> HostCheckResult {
        guard let executable = toolLocator.tuistURL() else {
            return HostCheckResult(kind: .tuist, status: .unavailable, detail: "Install Tuist with Homebrew")
        }
        do {
            let output = try await runner.run(.tuistVersion(executable: executable))
            return HostCheckResult(
                kind: .tuist,
                status: output.succeeded ? .ready : .unavailable,
                detail: summarized(output.text, fallback: "Tuist did not respond")
            )
        } catch {
            return HostCheckResult(kind: .tuist, status: .unavailable, detail: error.localizedDescription)
        }
    }

    private func inspectCodex() async -> HostCheckResult {
        guard let executable = toolLocator.codexURL() else {
            return HostCheckResult(kind: .codex, status: .warning, detail: "Codex CLI is optional; demo planning remains available")
        }
        do {
            let version = try await runner.run(.codexVersion(executable: executable))
            guard version.succeeded else {
                return HostCheckResult(kind: .codex, status: .warning, detail: summarized(version.text, fallback: "Codex CLI failed"))
            }
            let versionText = summarized(version.text, fallback: "Codex CLI")
            return HostCheckResult(
                kind: .codex,
                status: .ready,
                detail: "\(versionText); authentication is verified when a prompt runs"
            )
        } catch {
            return HostCheckResult(kind: .codex, status: .warning, detail: error.localizedDescription)
        }
    }

    private func inspectDevices(xcodeMajorVersion: Int?) async -> (check: HostCheckResult, devices: [DeploymentDevice]) {
        let jsonURL = fileManager.value.temporaryDirectory
            .appending(path: "builder-host-devices-\(UUID().uuidString).json")
        defer { try? fileManager.value.removeItem(at: jsonURL) }

        do {
            let output = try await runner.run(.listDevices(jsonURL: jsonURL))
            guard output.succeeded, let data = try? Data(contentsOf: jsonURL) else {
                return (
                    HostCheckResult(kind: .device, status: .unavailable, detail: summarized(output.text, fallback: "Unable to list devices")),
                    []
                )
            }
            let devices = try DeviceListParser.parse(data, xcodeMajorVersion: xcodeMajorVersion)
            let readyCount = devices.count(where: \.isReadyForInstallation)
            let check = HostCheckResult(
                kind: .device,
                status: readyCount == 0 ? .warning : .ready,
                detail: devices.isEmpty
                    ? "No paired iPhone or iPad is currently available"
                    : "\(readyCount) of \(devices.count) paired devices ready"
            )
            return (check, devices)
        } catch {
            return (HostCheckResult(kind: .device, status: .unavailable, detail: error.localizedDescription), [])
        }
    }

    private func summarized(_ text: String, fallback: String) -> String {
        let line = text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return String((line ?? fallback).prefix(180))
    }

    private func cleanIdentity(_ line: String) -> String {
        if let start = line.firstIndex(of: "\"") {
            let suffix = line[line.index(after: start)...]
            if let end = suffix.firstIndex(of: "\"") {
                return String(suffix[..<end])
            }
        }
        return "Apple Development identity available"
    }

    private static func majorVersion(in value: String) -> Int? {
        value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }
}

enum DeviceListParser {
    static func parse(_ data: Data, xcodeMajorVersion: Int?) throws -> [DeploymentDevice] {
        let document = try JSONDecoder().decode(DeviceDocument.self, from: data)
        return document.result.devices.compactMap { device in
            let kind: DeploymentDeviceKind
            switch device.hardwareProperties.deviceType {
            case "iPhone": kind = .iPhone
            case "iPad": kind = .iPad
            default: return nil
            }
            let operatingSystem = device.deviceProperties.osVersionNumber ?? "Unknown iOS"
            let deviceOSMajor = majorVersion(in: operatingSystem)
            let isSupported = xcodeMajorVersion.map { xcodeMajor in
                deviceOSMajor.map { $0 <= xcodeMajor } ?? true
            } ?? true
            return DeploymentDevice(
                id: device.identifier,
                name: device.deviceProperties.name ?? "Unknown \(kind.displayName)",
                kind: kind,
                operatingSystem: operatingSystem,
                connection: device.connectionProperties.transportType ?? "unknown",
                developerModeEnabled: device.deviceProperties.developerModeStatus?.lowercased() == "enabled",
                isSupportedByXcode: isSupported
            )
        }
    }

    private static func majorVersion(in value: String) -> Int? {
        value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }
}

private struct DeviceDocument: Decodable {
    let result: DeviceResult
}

private struct DeviceResult: Decodable {
    let devices: [DevicePayload]
}

private struct DevicePayload: Decodable {
    let identifier: String
    let deviceProperties: DeviceProperties
    let connectionProperties: ConnectionProperties
    let hardwareProperties: HardwareProperties
}

private struct DeviceProperties: Decodable {
    let name: String?
    let osVersionNumber: String?
    let developerModeStatus: String?
}

private struct ConnectionProperties: Decodable {
    let transportType: String?
}

private struct HardwareProperties: Decodable {
    let deviceType: String?
}
