# On-Device App Builder

Build and deploy SwiftUI prototypes from an iPhone or iPad while a trusted Mac performs the coding, testing, signing, and device installation locally.

## MVP

The first vertical slice contains:

- a native iPhone and iPad client for setup, projects, chat, approvals, and build status;
- a native macOS menu-bar host discovered over the local network;
- a shared, versioned protocol between client and host;
- deterministic Xcode, signing, and paired-device diagnostics; and
- a safe demo workflow that proves the prompt-to-build state machine before Codex execution is enabled.

## Product boundaries

- macOS is the only build host;
- source code and credentials stay on the user's Mac;
- no generic remote shell endpoint;
- no Windows or cloud build host; and
- no App Store submission in the MVP.

## Status

Initial repository created. The Tuist workspace and MVP implementation follow in the next commit.

