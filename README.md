# On-Device App Builder

Describe and steer a SwiftUI prototype from an iPhone or iPad while a trusted Mac performs source generation, Xcode builds, signing, and installation locally.

The phone is the control surface. The Mac remains the build machine and the security boundary.

> [!WARNING]
> **MVP – use on trusted networks only.** Sessions are encrypted, but there is no pairing or peer authentication yet: any nearby device that connects to Builder Host can send build and Codex requests. See [MVP limits](#mvp-limits).

## Screenshots and demo video

_Coming soon: screenshots of Phone Builder and Builder Host, plus a short demo video of a prompt-to-install run._

## MVP flow

1. Start **Builder Host** from the Mac menu bar.
2. Open **Phone Builder** on an iPhone or iPad on the same local network.
3. Connect to the discovered Mac and review Xcode, signing, Codex, and device checks.
4. Create a project, describe the app in chat, and follow the streamed run timeline.
5. Build the generated SwiftUI prototype, then choose a compatible paired iPhone or iPad for installation.
6. Remove old projects from the Projects list with a confirmed swipe-to-delete action.

The apps also include a deterministic demo mode so navigation and the complete project/chat/build state machine can be tested without invoking Codex.

## Requirements

- macOS 26 with Xcode 26 and Xcode Command Line Tools
- an Apple Development certificate and signing team
- [Tuist](https://tuist.dev) 4.205 or newer
- a paired iPhone or iPad with Developer Mode enabled
- optional: [Codex CLI](https://developers.openai.com/codex/noninteractive), signed in locally with `codex login` (ChatGPT) or `codex login --with-api-key`

No OpenAI or Apple credential is sent to the mobile app. Codex runs on the Mac and reuses its stored local login. Builder Host passes only a minimal environment to child processes, so an `OPENAI_API_KEY` exported in your shell is **not** forwarded; store the key with `codex login --with-api-key` instead.

## Build and run

### Signing configuration

Simulator builds need no signing setup. For device builds and for signing the generated prototypes, set your Apple Developer Team ID locally:

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# edit DEVELOPMENT_TEAM in Config/Signing.local.xcconfig (gitignored)
```

Builder Host reads the Team ID from its Info.plist (expanded from `DEVELOPMENT_TEAM`). To override it at runtime, set `BUILDER_DEVELOPMENT_TEAM`. Without a Team ID, prototype builds stop with a clear setup error.

### Build

```sh
brew install --cask tuist
tuist generate --no-open
tuist xcodebuild build -scheme BuilderHost -derivedDataPath .derived
tuist xcodebuild build -scheme PhoneBuilder \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derived
```

Start or stop the menu-bar host with:

```sh
./run-menubar.sh
./stop-menubar.sh
```

Open `OnDeviceAppBuilder.xcworkspace` for signing and physical-device runs.

### Demo mode (no Mac host or Codex needed)

Phone Builder ships a deterministic demo mode with a simulated Mac, paired devices, and the full project/chat/build/install timeline. Run it in the iOS Simulator by adding the launch argument `-demo-mode` (Xcode: Product › Scheme › Edit Scheme › Run › Arguments), or:

```sh
xcrun simctl launch booted dev.buberlo.ondeviceappbuilder.ios -demo-mode
```

Demo mode never invokes Codex or Xcode; it exercises UI and state only.

## Architecture and safety

- `BuilderCore` contains the versioned, typed protocol and encrypted nearby transport.
- `PhoneBuilder` contains the iPhone/iPad setup, projects, chat, and activity UI.
- `BuilderHost` contains diagnostics, Codex orchestration, controlled workspaces, builds, and installs.
- Multipeer Connectivity requires encrypted sessions; there is no arbitrary remote-shell endpoint.
- Generated workspaces live below the host app's Application Support directory.
- Codex runs with workspace-write sandboxing; this constrains writes, not general read access on the trusted Mac account.
- Installation is a separate typed action, never an implicit side effect of a prompt.
- Every installation request contains the selected device ID; the host never silently picks another device.
- Devices newer than the selected Xcode major version remain visible but are disabled with a compatibility warning.
- Codex, Tuist, and Xcode emit filtered live progress into the project log and Activity timeline.
- Project deletion is a typed operation, requires confirmation on the device, and is restricted to the host-owned workspace root.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the trust boundary and first vertical slice.

## MVP limits

- Mac-only host; no Windows or cloud build host
- SwiftUI prototype template only
- one trusted local host and one active run at a time
- no App Store submission, TestFlight upload, or automatic certificate creation
- local-network encryption is implemented; pairing, peer authentication, and durable device identity/pinning are post-MVP hardening items, so use it only on trusted networks

## License

[MIT](LICENSE) © 2026 Konrad Kern
