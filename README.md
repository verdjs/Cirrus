# Cirrus

A native unified game streaming client for Apple TV. Stream your Xbox Game Pass library via Xbox Cloud Gaming (xCloud) and your PC game library via NVIDIA GeForce NOW — all from one app, no browser, no workarounds.

> **Personal use / sideload only.** This project is not affiliated with, endorsed by, or sponsored by NVIDIA, Microsoft, or Xbox. NVIDIA, GeForce NOW, Xbox, and Xbox Game Pass are trademarks of their respective owners.

> [!WARNING]
> Cirrus is under active development. Expect bugs.

---

## What's Cirrus?

Cirrus merges two separate open-source Apple TV streaming clients — **CloudNow** (GeForce NOW) by [Owen Selles](https://github.com/owenselles) and **Stratix** (Xbox Cloud Gaming) by [nafields](https://github.com/nafields) — into a single unified tvOS app. See [credits.md](credits.md) for full attribution and [changes.md](changes.md) for a breakdown of what changed.

---

## Features

### Xbox Cloud Gaming (xCloud)
- Sign in with your Microsoft account via standard OAuth device flow
- Browse your full Xbox Game Pass catalog
- Launch and stream games via WebRTC using the LiveKit xCloud SDK
- Full controller support (MFi, Xbox, PlayStation) via GameController framework
- Configurable stream resolution, FPS, and diagnostics overlay

### GeForce NOW (GFN)
- Sign in via cloud.gg OAuth (QR code + PIN on TV, complete on any device)
- Browse your linked game library and the full public GFN catalog
- Stream up to 4K@60fps depending on your GFN plan
- Live stats overlay — bitrate, resolution, FPS, RTT, packet loss, session time
- Zone/region selection with live queue depths and ping scoring
- Codec-aware SDP negotiation (H.264 / H.265 / AV1)
- Queue position UI with ad playback during high-demand periods

### General
- Unified home screen with both services
- Full tvOS focus engine support
- Up to 4 simultaneous controllers
- Favorites system (long-press any game card)
- Keychain-persisted session tokens with auto-refresh
- Settings panel for per-service stream quality, region, and accessibility options

---

## Getting Started

### 1. Clone

```bash
git clone https://github.com/verdjs/Cirrus.git
cd Cirrus
```

### 2. Open in Xcode

Open `CloudNow.xcodeproj` in Xcode 16+.

Dependencies (LiveKit WebRTC, Swift Collections, Swift Async Algorithms, Swift Protobuf) are resolved automatically via Swift Package Manager on first open.

### 3. Set your Team ID

```bash
cp Local.xcconfig.example Local.xcconfig
```

Edit `Local.xcconfig` and replace `YOUR_TEAM_ID_HERE` with your Apple Developer Team ID (find it at [developer.apple.com](https://developer.apple.com) → Account → Membership).

`Local.xcconfig` is gitignored and should never be committed.

### 4. Build & Run

Select your Apple TV as the run destination (USB-C or network) and press **⌘R**.

---

## Architecture

```
CloudNow/
├── CloudXApp/
│   ├── Auth/                    Microsoft OAuth + GFN OAuth flows, Keychain persistence
│   ├── Features/
│   │   ├── CloudLibrary/        Unified game library UI (home, browse, settings)
│   │   ├── Streaming/           WebRTC session lifecycle, video rendering, input
│   │   └── Onboarding/          Sign-in flows for both services
│   └── Core/                    App coordinator, environment injection
cloudx/
└── Packages/                    Swift packages: CloudXCore, XCloudAPI, StreamingCore,
                                 VideoRenderingKit, DiagnosticsKit, InputBridge
```

---

## Credits

See [credits.md](credits.md) for full attribution to the original projects and contributors that made Cirrus possible.

---

## License

MIT — see [LICENSE](LICENSE).
