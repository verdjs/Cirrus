# Changes & GPL v3 Compliance Notice

Cirrus is a derivative work that incorporates and modifies source code from two GPL v3 licensed open-source projects. In accordance with the GNU General Public License v3, this document provides a complete record of the incorporated upstream works, the modifications made, and the license obligations of this project.

Cirrus is licensed under the **GNU General Public License v3.0 or later**. The full license text is available in the [LICENSE](LICENSE) file and at <https://www.gnu.org/licenses/gpl-3.0.html>.

---

## Incorporated Upstream Works

### 1. Stratix
- **Author**: nafields
- **Repository**: <https://github.com/nafields/stratix>
- **License**: GNU General Public License v3.0
- **Description**: A native Apple TV client for Xbox Cloud Gaming (xCloud / xHome) using WebRTC, LiveKit, and the Microsoft OAuth device flow.
- **Components incorporated into Cirrus**:
  - `cloudx/` — the full Stratix Swift package tree (CloudXCore, XCloudAPI, StreamingCore, VideoRenderingKit, DiagnosticsKit, InputBridge, CloudXModels)
  - `cloudx_backup/` — reference snapshot of Stratix packages prior to integration
  - Xbox Cloud Gaming authentication flow (Microsoft OAuth 2.0 device flow)
  - WebRTC session lifecycle, SDP negotiation, and ICE processing
  - Input bridge (XInput protocol over WebRTC data channel)
  - Metal video renderer and sample buffer display pipeline
  - Streaming session orchestration, reconnect policy, and diagnostics

### 2. CloudNow
- **Author**: Owen Selles
- **Repository**: <https://github.com/owenselles/CloudNow>
- **License**: MIT License (compatible with GPL v3 — MIT code may be incorporated into a GPL v3 work)
- **Description**: A native Apple TV client for NVIDIA GeForce NOW using WebRTC and the cloud.gg OAuth device flow.
- **Components incorporated into Cirrus**:
  - `CloudNow/` — the full CloudNow tvOS app source (Auth, Session, Streaming, Video, UI)
  - `CloudNow.xcodeproj/` — Xcode project, schemes, and asset catalogs
  - GeForce NOW authentication (cloud.gg OAuth 2.0 PKCE + device flow, Keychain persistence)
  - GFN session management (CloudMatch REST client, queue UI, zone/region selection)
  - GFN game catalog client (GraphQL persisted queries)
  - GFN WebRTC streaming (SDP munging, codec negotiation, input sender)
  - GFN live stats overlay and stream quality settings

---

## Third-Party Dependencies

The following libraries are used as dependencies and are **not** modified by Cirrus. They are fetched via Swift Package Manager at build time and are not vendored into this repository.

| Library | License | Used For |
|---------|---------|---------|
| [livekit/client-sdk-swift](https://github.com/livekit/client-sdk-swift) | Apache 2.0 | Xbox Cloud Gaming WebRTC transport |
| [livekit/webrtc-xcframework](https://github.com/livekit/webrtc-xcframework) | BSD-style (WebRTC) | WebRTC engine (GFN + Xbox) |
| [livekit/livekit-uniffi-xcframework](https://github.com/livekit/livekit-uniffi-xcframework) | Apache 2.0 | LiveKit Rust FFI bindings |
| [apple/swift-collections](https://github.com/apple/swift-collections) | Apache 2.0 | OrderedDictionary, Deque |
| [apple/swift-async-algorithms](https://github.com/apple/swift-async-algorithms) | Apache 2.0 | Async sequence utilities |
| [apple/swift-protobuf](https://github.com/apple/swift-protobuf) | Apache 2.0 | Protobuf serialization |

Apache 2.0 is compatible with GPL v3 — Apache 2.0 licensed code may be used in a GPL v3 work.

---

## Modifications Made to Upstream GPL v3 Code (Stratix)

The following changes were made to Stratix source code incorporated into Cirrus. All modifications are also released under GPL v3.

### 1. Project Structure & Integration
- Replaced `Stratix.xcworkspace` with `CloudNow.xcodeproj` as the unified build entry point, combining both the Stratix Swift packages (`cloudx/`) and the CloudNow tvOS app target into a single project
- Renamed app-facing target references from "Stratix" to "CloudNow" / "Cirrus" throughout the Xcode project

### 2. User Interface & Navigation
- Merged the Xbox Game Pass library view and GeForce NOW library grid into a unified `CloudLibraryView` dashboard
- Added a top navigation capsule bar with tabs for both streaming services and system status indicators
- Redesigned `CloudLibrarySettingsView.swift` to group Xbox Cloud Gaming, GeForce NOW, and General/Accessibility settings in a single unified settings interface
- Added an in-app Credits panel to `CloudLibrarySettingsView.swift` acknowledging all upstream authors and contributors

### 3. Streaming & Session Improvements
- Added high-quality backdrop blur effect to the xCloud connecting/loading view to match GFN stream transition aesthetics
- Integrated background catalog caching and token refresh cycles from the GFN side to reduce startup latency across both services
- Replaced full-screen block screens with non-blocking inline refresh indicators

### 4. Performance & Stability
- Set `upscalingEnabled = false` as the default in `SettingsStore.swift` to prevent frame drops on older hardware
- Removed onboarding walkthrough overlays and tutorial card dependencies to allow immediate app navigation on launch
- Replaced unstable `ZStack` background layers with native SwiftUI shape background bindings (`.background(.style, in: Shape)`) to fix layout issues on navigation bars and overlay panels

---

## Source Code Availability

In compliance with GPL v3 Section 6, the complete corresponding source code for Cirrus is publicly available at:

**<https://github.com/verdjs/Cirrus>**

You are free to copy, modify, and distribute this software under the terms of the GNU General Public License v3. Any distribution of Cirrus or a derivative work must also be accompanied by the complete corresponding source code and must be licensed under GPL v3.

---

## Original Copyright Notices

The following original copyright notices are preserved as required by GPL v3:

- Stratix — Copyright © 2026 nafields. Licensed under GPL v3.
- CloudNow — Copyright © 2026 Owen Selles. Licensed under MIT.
