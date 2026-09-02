# MVP architecture

The MVP uses three targets with strict boundaries:

1. `BuilderCore` owns versioned messages, domain models, setup snapshots, and the encrypted Multipeer Connectivity transport.
2. `PhoneBuilder` owns the iPhone/iPad experience: setup, projects, conversation, approvals, and build progress.
3. `BuilderHost` owns the Mac menu-bar lifecycle, diagnostics, workspace changes, Xcode processes, and device deployment.

The Mac is authoritative. The phone caches presentation state only and can replay missed events after reconnecting.

## Security boundary

- Multipeer Connectivity requires encrypted sessions.
- Provider and Apple credentials never appear in protocol payloads.
- Requests are typed; there is no arbitrary shell request.
- Workspaces are created below one application-owned root.
- Deletion resolves a known project ID and revalidates its path before removing that one workspace directory.
- Installation is a distinct, user-approved action.
- The host publishes all paired iPhone and iPad targets with readiness metadata. The phone sends the exact selected device ID with each install request.

The MVP deliberately separates transport encryption from durable trust. Multipeer Connectivity protects the session in transit. A production release must additionally persist and verify a host identity (for example, a pairing secret or pinned public key) before accepting privileged commands.

## Codex boundary

The host starts Codex in the selected project directory with an explicit workspace-write sandbox. That sandbox restricts writes, while the host prompt separately instructs Codex not to read secrets or files outside the project. It reuses the Codex CLI authentication already stored on the Mac; authentication material is never read by Builder Host or copied into a protocol message. JSONL progress is translated into typed, user-facing events.

If Codex is missing, signed out, or unhealthy, the host reports that setup check and uses the deterministic demo planner. The demo path exercises UI and transport state without pretending that an AI run occurred.

## Controlled execution

The host exposes operations, not commands:

- diagnose the supported toolchain;
- create a project inside the owned workspace root;
- delete a known project and its build artifacts from that root;
- ask Codex to edit that project;
- generate and build the known Tuist project;
- install a specific built `.app` on a paired device; and
- launch the known bundle identifier.

Every executable and argument list is constructed by the host. Phone-provided strings are treated as data and never interpolated into a shell program.

## First vertical slice

The first end-to-end workflow is intentionally narrow:

1. Discover and connect to the local Mac host.
2. Receive deterministic Xcode, signing, Codex, and device readiness checks.
3. Create a SwiftUI prototype project from the phone.
4. Submit an idea and receive streamed plan/build events.
5. Review the result, choose a compatible iPhone or iPad, and explicitly request installation.
6. Confirm deletion of obsolete projects from the project list.

## Post-MVP hardening

1. Add an out-of-band pairing code and pin the Mac identity in Keychain.
2. Add resumable event logs with sequence acknowledgements.
3. Present and approve source diffs before privileged Codex or install phases.
4. Move long-running work into a launch agent that survives menu-bar UI restarts.
5. Add certificate/provisioning remediation without ever exporting private keys.
