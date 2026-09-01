# On-Device App Builder

Describe and steer a SwiftUI prototype from an iPhone or iPad while a trusted Mac performs source generation, Xcode builds, signing, and installation locally.

The phone is the control surface. The Mac remains the build machine and the security boundary.

## MVP flow

1. Start **Builder Host** from the Mac menu bar.
2. Open **Phone Builder** on an iPhone or iPad on the same local network.
3. Connect to the discovered Mac and review Xcode, signing, Codex, and device checks.
4. Create a project, describe the app in chat, and follow the streamed run timeline.
5. Build the generated SwiftUI prototype and explicitly request installation on a paired iPhone.

The apps also include a deterministic demo mode so navigation and the complete project/chat/build state machine can be tested without invoking Codex.

## Requirements

- macOS 26 with Xcode 26 and Xcode Command Line Tools
- an Apple Development certificate and signing team
- [Tuist](https://tuist.dev) 4.205 or newer
- a paired iPhone or iPad with Developer Mode enabled
- optional: [Codex CLI](https://developers.openai.com/codex/noninteractive), signed in locally with ChatGPT or an API key

No OpenAI or Apple credential is sent to the mobile app. Codex runs on the Mac and reuses its local authentication.

## Build and run

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

## Architecture and safety

- `BuilderCore` contains the versioned, typed protocol and encrypted nearby transport.
- `PhoneBuilder` contains the iPhone/iPad setup, projects, chat, and activity UI.
- `BuilderHost` contains diagnostics, Codex orchestration, controlled workspaces, builds, and installs.
- Multipeer Connectivity requires encrypted sessions; there is no arbitrary remote-shell endpoint.
- Generated workspaces live below the host app's Application Support directory.
- Codex runs with workspace-write sandboxing; this constrains writes, not general read access on the trusted Mac account.
- Installation is a separate typed action, never an implicit side effect of a prompt.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the trust boundary and first vertical slice.

## MVP limits

- Mac-only host; no Windows or cloud build host
- SwiftUI prototype template only
- one trusted local host and one active run at a time
- no App Store submission, TestFlight upload, or automatic certificate creation
- local-network encryption is implemented; durable device identity/pinning is a post-MVP hardening item
