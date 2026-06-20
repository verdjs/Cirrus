import Charts
import SwiftUI
import CloudXCore

private enum LoadingPhase: Equatable {
    case finding
    case inQueue(Int?)
    case preparing
    case timedOut
}

struct StreamView: View {
    let game: GameInfo
    var settings: StreamSettings = StreamSettings()
    var existingSession: ActiveSessionInfo? = nil
    /// When set, skips CloudMatch entirely and reconnects WebRTC directly using the stored session.
    var directSession: SessionInfo? = nil
    let onDismiss: () -> Void
    /// Called when the user leaves without ending the session so the caller can offer a resume.
    var onLeave: ((GameInfo, SessionInfo) -> Void)? = nil

    @Environment(AuthManager.self) var authManager
    @Environment(GamesViewModel.self) var viewModel
    @Environment(SettingsStore.self) private var settingsStore
    @State private var streamController = GFNStreamController()
    @State private var showOverlay = false
    @State private var showVirtualKeyboard = false
    @State private var showExitConfirmation = false
    @State private var loadingPhase: LoadingPhase = .finding
    @State private var createdSession: SessionInfo?
    @State private var sessionToken: String?
    // Per-ad state tracking to avoid duplicate reports
    @State private var adReportedAction: [String: AdAction] = [:]
    @State private var logLines: [String] = []
    @State private var showStatsLocal = false

    private let cloudMatchClient = CloudMatchClient()

    private func log(_ message: String) {
        print("[StreamViewLog] \(message)")
        DispatchQueue.main.async {
            logLines.append(message)
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.lowercased().contains("error") || line.lowercased().contains("failed") {
            return .red
        }
        if line.lowercased().contains("ready") || line.lowercased().contains("success") || line.lowercased().contains("connected") {
            return .green
        }
        if line.lowercased().contains("polling") {
            return .yellow.opacity(0.8)
        }
        return .white.opacity(0.8)
    }

    var body: some View {
        StreamControllerInputHost(onOverlayToggle: {
            toggleOverlay()
        }, onMenuPress: {
            if streamController.state == .streaming {
                toggleOverlay()
            } else {
                disconnect()
            }
        }, onDownPress: {
            if showOverlay {
                disconnect()
            }
        }) {
            ZStack {
                Color.black.ignoresSafeArea()

                if streamController.state == .idle || streamController.state == .connecting {
                    ambientBackground
                }

                switch streamController.state {
                case .idle, .connecting:
                    connectingView
                case .streaming:
                    streamingView
                case .disconnected(let reason):
                    disconnectedView(reason)
                case .failed(let message):
                    failedView(message)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .task {
            streamController.onStatsToggle = {
                settingsStore.stream.showStreamStats.toggle()
                showStatsLocal = settingsStore.stream.showStreamStats
            }
            await startSession()
        }
        .onDisappear { streamController.disconnect() }
        // During streaming, VideoSurfaceView is first responder and intercepts Menu via UIKit,
        // signaling us through menuPressCount. .onExitCommand only fires in non-streaming states
        // (loading, error) when the focus engine is active.
        .onChange(of: streamController.menuPressCount) { _, _ in
            toggleOverlay()
        }
        .onChange(of: settingsStore.stream.showStreamStats, initial: true) { _, newValue in
            showStatsLocal = newValue
        }
        .onExitCommand {
            if streamController.state != .streaming {
                disconnect()
            }
        }
    }

    // MARK: Connecting

    private var connectingView: some View {
        VStack(spacing: 32) {
            Spacer()

            if case .timedOut = loadingPhase {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
                    .scaleEffect(2.5)
                    .tint(.white)
            }

            VStack(spacing: 12) {
                Text(game.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)

                Text(loadingLabel)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .animation(.easeInOut, value: loadingPhase)
            }

            // Show ad player when GFN requires watching an ad to stay in queue
            if let adState = createdSession?.adState,
               adState.isAdsRequired,
               let ad = adState.ads.first {
                QueueAdPlayerView(
                    ad: ad,
                    onStart:  { id in reportAd(id: id, action: .start)  },
                    onPause:  { id in reportAd(id: id, action: .pause)  },
                    onResume: { id in reportAd(id: id, action: .resume) },
                    onFinish: { id, ms in reportAd(id: id, action: .finish, watchedMs: ms) },
                    message:  adState.message
                )
                .frame(maxWidth: 560)
                .padding(.top, 20)
            }

            Spacer()

            HStack(spacing: 24) {
                if case .timedOut = loadingPhase {
                    Button("Retry") { Task { await startSession() } }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                }
                Button("Cancel") { disconnect() }
                    .buttonStyle(.bordered)
                    .tint(loadingPhase == .timedOut ? .red : .secondary)
            }
            .padding(.bottom, 60)
        }
    }

    private var ambientBackground: some View {
        ZStack {
            if let imageUrlString = game.heroBannerUrl ?? game.boxArtUrl,
               let imageUrl = URL(string: imageUrlString) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                            .blur(radius: 40, opaque: true)
                            .opacity(0.35)
                    default:
                        EmptyView()
                    }
                }
            }
            RadialGradient(
                colors: [.clear, .black.opacity(0.8)],
                center: .center,
                startRadius: 200,
                endRadius: 800
            )
            .ignoresSafeArea()
        }
    }

    private var loadingLabel: String {
        switch loadingPhase {
        case .finding:
            return "Connecting to a GeForce NOW server…"
        case .inQueue(let pos):
            if let pos {
                if pos <= 0 { return "You're next!" }
                return "In queue · Position \(pos)"
            }
            return "In queue…"
        case .preparing:
            return "You're next!"
        case .timedOut:
            return "Server took too long to respond."
        }
    }

    // MARK: Streaming

    private var streamingView: some View {
        ZStack {
            VideoSurfaceViewRepresentable(streamController: streamController, showOverlay: showOverlay)
                .ignoresSafeArea()

            if showOverlay {
                pauseMenu
                    .transition(.opacity)
            }

            if showOverlay && showVirtualKeyboard {
                VStack {
                    Spacer()
                    VirtualKeyboardView(streamController: streamController)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea()
            }

            if let warning = streamController.timeWarning, !showOverlay {
                timeWarningBanner(warning)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if showStatsLocal && !showOverlay {
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FPS: \(Int(streamController.stats.fps))")
                            Text("RTT: \(Int(streamController.stats.rttMs)) ms")
                            Text("Bitrate: \(streamController.stats.bitrateKbps / 1000) Mbps")
                            Text("Loss: \(String(format: "%.1f", streamController.stats.packetLossPercent))%")
                            Text("Resolution: \(streamController.stats.resolutionWidth)×\(streamController.stats.resolutionHeight)")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color.white)
                        .padding(20)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: streamController.timeWarning)
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
        .animation(.easeInOut(duration: 0.2), value: showVirtualKeyboard)
        .onChange(of: showOverlay) { _, showing in
            // Pause game input while overlay is open so D-pad and trackpad
            // navigates overlay buttons instead of moving the in-game character/cursor.
            streamController.setInputPaused(showing)
            if !showing {
                showVirtualKeyboard = false
            }
        }
        .alert("End Session?", isPresented: $showExitConfirmation) {
            Button("End Session", role: .destructive) { disconnect() }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("This will end your GeForce NOW session. To return later, use Leave Game instead.")
        }
    }

    // MARK: Pause Menu

    private var pauseMenu: some View {
        HStack(alignment: .top, spacing: 40) {
            // Actions
            VStack(spacing: 16) {
                Button {
                    toggleOverlay()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    streamController.toggleRemoteMode()
                } label: {
                    Label(remoteModeLabel, systemImage: remoteModeIcon)
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)

                Button {
                    showVirtualKeyboard.toggle()
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(showVirtualKeyboard ? .blue : .white)

                Button {
                    leave()
                } label: {
                    Label("Leave Game", systemImage: "house")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)

                Button(role: .destructive) {
                    showExitConfirmation = true
                } label: {
                    Label("End Session", systemImage: "xmark.circle")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Live stats
            VStack(alignment: .leading, spacing: 10) {
                metricRow(
                    icon: "network",
                    label: "RTT",
                    value: "\(Int(streamController.stats.rttMs)) ms",
                    history: streamController.pingHistory,
                    color: pingColor(streamController.stats.rttMs)
                )
                metricRow(
                    icon: "speedometer",
                    label: "FPS",
                    value: "\(Int(streamController.stats.fps))",
                    history: streamController.fpsHistory,
                    color: fpsColor(streamController.stats.fps)
                )
                metricRow(
                    icon: "wifi",
                    label: "Bitrate",
                    value: "\(streamController.stats.bitrateKbps / 1000) Mbps",
                    history: streamController.bitrateHistory,
                    color: .cyan
                )
                Divider().overlay(.white.opacity(0.4))
                Label("\(streamController.stats.resolutionWidth)×\(streamController.stats.resolutionHeight) @ \(Int(streamController.stats.fps))fps", systemImage: "tv")
                Label("Loss \(String(format: "%.1f", streamController.stats.packetLossPercent))%", systemImage: "arrow.triangle.2.circlepath")
                if !streamController.stats.gpuType.isEmpty {
                    Label(streamController.stats.gpuType, systemImage: "cpu")
                }
                if let sub = viewModel.subscription, !sub.isUnlimited, let rem = sub.remainingMinutes {
                    Divider().overlay(.white.opacity(0.4))
                    Label {
                        Text(rem >= 60 ? "\(rem / 60)h \(rem % 60)m remaining" : "\(rem)m remaining")
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundStyle(rem < 30 ? .orange : .white.opacity(0.7))
                    }
                    .foregroundStyle(rem < 30 ? .orange : .white)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
        }
        .padding(32)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showVirtualKeyboard ? .top : .center)
        .padding(.top, showVirtualKeyboard ? 60 : 0)
        .padding(60)
    }

    private var remoteModeLabel: String {
        switch streamController.remoteMode {
        case .mouse:     return "Remote: Mouse"
        case .gamepad:   return "Remote: Gamepad"
        case .dualsense: return "Remote: DualSense"
        }
    }

    private var remoteModeIcon: String {
        switch streamController.remoteMode {
        case .mouse:     return "cursorarrow"
        case .gamepad:   return "gamecontroller"
        case .dualsense: return "hand.point.up.left"
        }
    }

    private func metricRow(icon: String, label: String, value: String, history: [Double], color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            Text("\(label): \(value)")
                .foregroundStyle(color)
                .frame(width: 130, alignment: .leading)
            if history.count > 1 {
                Chart {
                    ForEach(Array(history.enumerated()), id: \.offset) { (idx, val) in
                        LineMark(x: .value("t", idx), y: .value("v", val))
                            .foregroundStyle(color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 80, height: 24)
            }
        }
    }

    private func pingColor(_ ms: Double) -> Color {
        if ms < 30  { return .green }
        if ms < 80  { return .yellow }
        if ms < 150 { return .orange }
        return .red
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }

    // MARK: Time Warning Banner

    private func timeWarningBanner(_ warning: StreamTimeWarning) -> some View {
        let (color, icon, message): (Color, String, String) = {
            let timeText = warning.secondsLeft.map { " (\($0)s left)" } ?? ""
            switch warning.code {
            case 3: return (.red,    "clock.badge.xmark",     "Session ending soon\(timeText)")
            case 2: return (.orange, "clock.badge.exclamationmark", "~5 minutes remaining\(timeText)")
            default: return (.yellow, "clock",                "Session limit approaching\(timeText)")
            }
        }()
        return Label(message, systemImage: icon)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(color.opacity(0.85), in: Capsule())
            .padding(.top, 40)
    }

    // MARK: Disconnected / Failed

    private func disconnectedView(_ reason: String) -> some View {
        statusView(
            icon: "wifi.slash",
            title: "Disconnected",
            message: reason,
            color: .yellow
        )
    }

    private func failedView(_ message: String) -> some View {
        statusView(
            icon: "exclamationmark.triangle",
            title: "Stream Failed",
            message: entitlementMessage(from: message),
            color: .red
        )
    }

    private func entitlementMessage(from raw: String) -> String {
        if raw.uppercased().contains("ENTITLEMENT") || raw.contains("3237093650") {
            return "\(game.title) is not in your GeForce NOW library."
        }
        if raw.contains("SESSION_LIMIT_EXCEEDED") {
            return "A previous session is still active. Please wait a moment and try again."
        }
        return raw
    }

    private func statusView(icon: String, title: String, message: String, color: Color) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(color)
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button("Retry") { Task { await startSession() } }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                Button("Exit") { disconnect() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding(60)
    }

    // MARK: Actions

    private func startSession() async {
        logLines.removeAll()
        log("Starting stream session setup for game: \(game.title)...")
        log("Stream settings: resolution=\(settings.resolution) fps=\(settings.fps) bitrate=\(settings.maxBitrateKbps)kbps codec=\(settings.codec.rawValue)")
        // Reset stream controller (handles retry from failed/disconnected state)
        streamController.disconnect()

        // Reconnect path — RESUME PUT tells the server to rebuild its media endpoint,
        // then connect WebRTC as soon as we get a single status 2/3 (no double-poll wait).
        if let direct = directSession {
            loadingPhase = .preparing
            log("Direct session mode active.")
            do {
                log("Resolving authorization token...")
                let token = try await authManager.resolveToken()
                sessionToken = token
                let provider = authManager.session?.provider
                let streamingBaseUrl = provider?.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
                let base = streamingBaseUrl.hasSuffix("/") ? String(streamingBaseUrl.dropLast()) : streamingBaseUrl
                log("Base streaming service URL: \(base)")

                log("Claiming direct session \(direct.sessionId) on \(direct.serverIp)...")
                var sessionInfo = try await cloudMatchClient.claimSession(
                    sessionId: direct.sessionId,
                    serverIp: direct.serverIp,
                    token: token,
                    base: base,
                    settings: settings
                )
                createdSession = sessionInfo
                log("Claimed session. Current status: \(sessionInfo.status)")

                // Poll until ready, but only need a single status 2/3 (server media is up).
                while sessionInfo.status != 2 && sessionInfo.status != 3 {
                    log("Polling session... status=\(sessionInfo.status), queuePosition=\(sessionInfo.queuePosition ?? -1), seatSetupStep=\(sessionInfo.seatSetupStep ?? -1)")
                    try await Task.sleep(for: .seconds(2))
                    sessionInfo = try await cloudMatchClient.pollSession(
                        sessionId: sessionInfo.sessionId,
                        token: token,
                        base: sessionInfo.streamingBaseUrl,
                        serverIp: sessionInfo.serverIp.isEmpty ? nil : sessionInfo.serverIp,
                        clientId: sessionInfo.clientId,
                        deviceId: sessionInfo.deviceId
                    )
                    createdSession = sessionInfo
                }

                log("Session ready! Status: \(sessionInfo.status), Server IP: \(sessionInfo.serverIp)")
                viewModel.recordPlayed(game)
                log("Connecting WebRTC stream controller...")
                await streamController.connect(session: sessionInfo, settings: settings)
                log("WebRTC stream controller connected successfully.")
            } catch {
                log("Error during direct session connect: \(error.localizedDescription)")
                streamController.fail(with: error.localizedDescription)
            }
            return
        }

        // Stop any previously created server session before opening a new one.
        // Skip for resume — we want to keep the existing session alive.
        if let session = createdSession, let token = sessionToken, existingSession == nil {
            log("Stopping previous session \(session.sessionId) to avoid limit conflicts...")
            try? await cloudMatchClient.stopSession(
                sessionId: session.sessionId, token: token, base: session.streamingBaseUrl
            )
        }
        createdSession = nil
        loadingPhase = .finding
        do {
            log("Resolving authorization token...")
            let token = try await authManager.resolveToken()
            sessionToken = token
            let provider = authManager.session?.provider
            let streamingBaseUrl = provider?.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
            let base = streamingBaseUrl.hasSuffix("/") ? String(streamingBaseUrl.dropLast()) : streamingBaseUrl
            log("Base streaming service URL: \(base)")

            var effectiveExistingSession = existingSession

            if effectiveExistingSession == nil {
                log("Checking for active sessions on server...")
                let activeSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []
                log("Found \(activeSessions.count) active sessions.")
                
                // 1. Is there an active session for the SAME game?
                let matching = activeSessions.first { session in
                    game.variants.contains { v in
                        guard let appId = v.appId, let sessionAppId = session.appId else { return false }
                        return appId == sessionAppId
                    }
                }
                
                if let matching {
                    log("Active session found for the same game (\(game.title)). Resuming...")
                    effectiveExistingSession = matching
                } else {
                    // 2. Stop active sessions for DIFFERENT games to prevent limit conflicts
                    for session in activeSessions {
                        log("Stopping active session for a different game (Session ID: \(session.sessionId))...")
                        try? await cloudMatchClient.stopSession(
                            sessionId: session.sessionId,
                            token: token,
                            base: base
                        )
                    }
                }
            }

            var sessionInfo: SessionInfo

            if let existing = effectiveExistingSession {
                let serverIp = existing.serverIp ?? URL(string: base)?.host ?? ""
                log("Resuming existing session: ID=\(existing.sessionId), IP=\(serverIp)")
                sessionInfo = try await cloudMatchClient.claimSession(
                    sessionId: existing.sessionId,
                    serverIp: serverIp,
                    token: token,
                    base: base,
                    settings: settings
                )
                log("Claimed session. Current status: \(sessionInfo.status)")
            } else {
                guard let appId = game.variants.first?.appId ?? game.variants.first?.id else {
                    log("Error: Could not determine app ID for variants.")
                    return
                }
                log("Requesting new session. App ID: \(appId)")

                // Prefer the user-selected zone URL; fall back to the provider's default.
                let sessionBase = settings.preferredZoneUrl ?? base
                log("VPC Zone/Base URL: \(sessionBase)")

                let request = SessionCreateRequest(
                    appId: appId,
                    internalTitle: game.title,
                    token: token,
                    zone: "",
                    streamingBaseUrl: sessionBase,
                    settings: settings,
                    accountLinked: true
                )

                do {
                    log("Calling createSession...")
                    sessionInfo = try await cloudMatchClient.createSession(request)
                    log("Session created successfully. ID: \(sessionInfo.sessionId), Status: \(sessionInfo.status)")
                } catch CloudMatchError.sessionCreateFailed(let msg) where msg.contains("SESSION_LIMIT_EXCEEDED") {
                    log("Session limit exceeded. Finding and stopping stale sessions...")
                    let staleSessions = (try? await cloudMatchClient.getActiveSessions(token: token, base: base)) ?? []
                    log("Found \(staleSessions.count) stale sessions to terminate.")
                    for stale in staleSessions {
                        log("Stopping stale session \(stale.sessionId)...")
                        try? await cloudMatchClient.stopSession(sessionId: stale.sessionId, token: token, base: base)
                    }
                    log("Retrying createSession...")
                    sessionInfo = try await cloudMatchClient.createSession(request)
                    log("Session created successfully on retry. ID: \(sessionInfo.sessionId), Status: \(sessionInfo.status)")
                }
            }
            createdSession = sessionInfo

            // Poll with readyPollStreak confirmation (requires 2 consecutive ready polls).
            // While in queue: no timeout — user waits indefinitely with position updates.
            var readyPollStreak = 0

            log("Entering polling loop. Waiting for resources/session activation...")
            while readyPollStreak < 2 {
                if sessionInfo.isInQueue {
                    loadingPhase = .inQueue(sessionInfo.queuePosition)
                    log("Polling queue status: queuePosition=\(sessionInfo.queuePosition ?? -1), seatSetupStep=\(sessionInfo.seatSetupStep ?? -1), status=\(sessionInfo.status)")
                } else {
                    loadingPhase = .preparing
                    log("Polling preparation status: status=\(sessionInfo.status), seatSetupStep=\(sessionInfo.seatSetupStep ?? -1)")
                }

                if sessionInfo.status == 2 || sessionInfo.status == 3 {
                    readyPollStreak += 1
                    log("Ready state detected (streak \(readyPollStreak)/2). status=\(sessionInfo.status)")
                } else {
                    readyPollStreak = 0
                }

                if readyPollStreak >= 2 { break }

                try await Task.sleep(for: .seconds(2))
                log("Polling API endpoint...")
                sessionInfo = try await cloudMatchClient.pollSession(
                    sessionId: sessionInfo.sessionId,
                    token: token,
                    base: sessionInfo.streamingBaseUrl,
                    serverIp: sessionInfo.serverIp.isEmpty ? nil : sessionInfo.serverIp,
                    clientId: sessionInfo.clientId,
                    deviceId: sessionInfo.deviceId
                )
                createdSession = sessionInfo
            }

            log("Session resources assigned and active. Server IP: \(sessionInfo.serverIp)")
            viewModel.recordPlayed(game)
            log("Connecting WebRTC stream controller...")
            await streamController.connect(session: sessionInfo, settings: settings)
            log("WebRTC stream controller connected successfully.")
        } catch {
            log("Session launch failed with error: \(error.localizedDescription)")
            streamController.fail(with: error.localizedDescription)
        }
    }

    // Leaves the stream locally without stopping the server session.
    // GFN keeps the session alive for ~1–2 minutes so it can be resumed from home.
    private func leave() {
        if let session = createdSession {
            onLeave?(game, session)
        }
        streamController.disconnect()
        onDismiss()
    }

    private func disconnect() {
        // Intentional end — clear any pending resumable session
        viewModel.resumableSession = nil
        // Tell the server to stop the session so it doesn't linger
        if let session = createdSession, let token = sessionToken {
            Task {
                try? await cloudMatchClient.stopSession(
                    sessionId: session.sessionId,
                    token: token,
                    base: session.streamingBaseUrl
                )
            }
        }
        streamController.disconnect()
        onDismiss()
    }

    private func reportAd(id: String, action: AdAction, watchedMs: Int? = nil) {
        // Prevent duplicate reports for the same action on the same ad
        guard adReportedAction[id] != action else { return }
        adReportedAction[id] = action
        guard let session = createdSession, let token = sessionToken else { return }
        Task {
            await cloudMatchClient.reportAdEvent(
                sessionId: session.sessionId,
                token: token,
                base: session.streamingBaseUrl,
                serverIp: session.serverIp.isEmpty ? nil : session.serverIp,
                clientId: session.clientId,
                deviceId: session.deviceId,
                adId: id,
                action: action,
                watchedTimeMs: watchedMs
            )
        }
    }

    private func toggleOverlay() {
        showOverlay.toggle()
        if !showOverlay {
            showVirtualKeyboard = false
        }
        // Pause input forwarding while the overlay is visible so swipes don't move
        // the game cursor and keyboard shortcuts don't reach the game accidentally.
        streamController.setInputPaused(showOverlay)
    }
}
