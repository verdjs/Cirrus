// AuthenticatedShellView.swift
// Defines the authenticated shell container and its lightweight runtime markers.
//

import SwiftUI
import CloudXCore
import CloudXModels

/// Hosts the authenticated shell and publishes lightweight readiness markers used by shell UI tests.
struct AuthenticatedShellView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(StreamController.self) private var streamController
    @Environment(ShellBootstrapController.self) private var shellBootstrapController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AuthManager.self) private var authManager
    @Environment(GamesViewModel.self) private var gamesViewModel
    @Environment(SessionController.self) private var sessionController

    /// Renders the authenticated shell, root content, and hidden state markers used by tests.
    var body: some View {
        @Bindable var bindableGamesViewModel = gamesViewModel
        @Bindable var bindableAuthManager = authManager
        
        ZStack {
            CloudLibraryView()
            
            if shellBootstrapController.initialHydrationInProgress {
                StartupLoadingView(statusText: shellBootstrapController.statusText)
                    .transition(.opacity)
            }
            
            shellReadyMarker
            streamExitCompletionMarker
        }
        .animation(.default, value: shellBootstrapController.phase)
        .fullScreenCover(item: $bindableGamesViewModel.activeGFNGame) { game in
            StreamView(
                game: game,
                settings: gamesViewModel.streamSettings,
                onDismiss: {
                    gamesViewModel.activeGFNGame = nil
                },
                onLeave: { game, session in
                    gamesViewModel.activeGFNGame = nil
                    gamesViewModel.resumableSession = ResumableSession(game: game, session: session, leftAt: Date())
                }
            )
            .environment(authManager)
            .environment(gamesViewModel)
            .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: Binding(
            get: { authManager.loginPhase != .idle },
            set: { if !$0 { authManager.cancelLogin() } }
        )) {
            LoginView()
                .environment(authManager)
        }
        .fullScreenCover(isPresented: Binding(
            get: {
                if case .authenticating = sessionController.authState { return true }
                return false
            },
            set: { _ in }
        )) {
            if case .authenticating(let info) = sessionController.authState {
                DeviceCodeView(info: info)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CloudXPortalReturnNotification"))) { _ in
            authManager.cancelLogin()
        }
        .task {
            if authManager.isAuthenticated {
                await gamesViewModel.load(authManager: authManager)
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthed in
            if isAuthed {
                Task { await gamesViewModel.load(authManager: authManager) }
            }
        }
        .dynamicTypeSize(
            authenticatedShellEffectiveDynamicTypeSize(
                base: dynamicTypeSize,
                largeTextEnabled: settingsStore.accessibility.largeText
            )
        )
        .transaction {
            if settingsStore.accessibility.reduceMotion {
                $0.animation = nil
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    /// Exposes shell readiness to UI tests without affecting visible layout.
    private var shellReadyMarker: some View {
        if shellBootstrapController.phase == .ready {
            Text("shell_ready")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("shell_ready")
                .accessibilityValue("ready")
        }
    }

    @ViewBuilder
    /// Exposes stream-exit completion to UI tests after the shell has been restored.
    private var streamExitCompletionMarker: some View {
        if streamController.shellRestoredAfterStreamExit {
            Text("shell_restored_after_stream_exit")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("stream_exit_complete")
                .accessibilityValue("shell_restored")
        }
    }
}

@MainActor
/// Produces the compact settings summary displayed in profile and shell surfaces.
func authenticatedShellSettingsSummary(settingsStore: SettingsStore) -> String {
    let latency = settingsStore.stream.lowLatencyMode ? "Low latency" : "Balanced latency"
    let stats = settingsStore.stream.showStreamStats ? "Stats on" : "Stats off"
    return "\(settingsStore.stream.qualityPreset) • \(settingsStore.stream.codecPreference) • \(latency) • \(stats)"
}

@MainActor
/// Clamps Dynamic Type up to the large-text floor when that accessibility option is enabled.
func authenticatedShellEffectiveDynamicTypeSize(
    base: DynamicTypeSize,
    largeTextEnabled: Bool
) -> DynamicTypeSize {
    guard largeTextEnabled else { return base }
    return max(base, .xLarge)
}

@MainActor
/// Derives a short initials string for profile fallback rendering.
func authenticatedShellInitials(from name: String) -> String {
    let initials = name
        .split(separator: " ")
        .prefix(2)
        .compactMap { $0.first.map(String.init) }
        .joined()
        .uppercased()
    return initials.isEmpty ? "P" : initials
}

@MainActor
/// Chooses the best display name for the signed-in profile and falls back to the settings store.
func authenticatedShellEffectiveProfileName(
    profileSnapshot: ProfileShellSnapshot,
    settingsStore: SettingsStore
) -> String {
    if let preferred = profileSnapshot.preferredScreenName?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !preferred.isEmpty {
        return preferred
    }
    return settingsStore.shell.profileName
}

@MainActor
/// Chooses the best profile image URL between live profile data and the shell fallback.
func authenticatedShellEffectiveProfileImageURL(
    profileSnapshot: ProfileShellSnapshot,
    settingsStore: SettingsStore
) -> URL? {
    profileSnapshot.profileImageURL ?? settingsStore.profileImageURL
}

@MainActor
/// Normalizes profile presence into the shell-facing Online or Offline status text.
func authenticatedShellProfilePresenceStatus(
    profileSnapshot: ProfileShellSnapshot,
    libraryStatus: LibraryShellStatusSnapshot,
    settingsStore: SettingsStore
) -> String {
    let override = settingsStore.shell.profilePresenceOverride
    if override == "Online" || override == "Offline" {
        return override
    }
    if let liveState = profileSnapshot.presenceState,
       !liveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return liveState.capitalized
    }
    if libraryStatus.needsReauth {
        return "Offline"
    }
    if libraryStatus.lastErrorText != nil,
       libraryStatus.hasSections == false,
       libraryStatus.isLoading == false {
        return "Offline"
    }
    return "Online"
}

@MainActor
/// Produces the longer profile presence detail string used in the authenticated shell.
func authenticatedShellProfilePresenceDetailText(profileSnapshot: ProfileShellSnapshot) -> String {
    if profileSnapshot.isLoadingCurrentUserPresence, profileSnapshot.presenceState == nil {
        return "Syncing Xbox presence…"
    }

    if let activeTitle = profileSnapshot.activeTitleName, profileSnapshot.isOnline {
        return "Playing \(activeTitle)"
    }
    if let lastSeen = profileSnapshot.lastSeenTitleName, !lastSeen.isEmpty {
        return "Last seen in \(lastSeen)"
    }
    if let device = profileSnapshot.onlineDeviceType, !device.isEmpty, profileSnapshot.isOnline {
        return "Online on \(device)"
    }

    if let error = profileSnapshot.lastCurrentUserPresenceError, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if error.localizedCaseInsensitiveContains("decode") || error.localizedCaseInsensitiveContains("format") {
            return "Xbox status sync unavailable"
        }
        return "Xbox presence unavailable"
    }

    return "Xbox presence synced"
}

struct StartupLoadingView: View {
    let statusText: String?
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.25).opacity(0.6),
                    Color.black
                ]),
                center: .center,
                startRadius: 100,
                endRadius: 900
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.white, .white.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color.blue.opacity(0.15), radius: 20, x: 0, y: 10)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                Text(statusText ?? "Loading Cirrus...")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .animation(.easeInOut, value: statusText)
            }
        }
    }
}

#if DEBUG
private struct AuthenticatedShellPreviewHost: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        AuthenticatedShellView()
            .environment(coordinator.sessionController)
            .environment(coordinator.libraryController)
            .environment(coordinator.profileController)
            .environment(coordinator.consoleController)
            .environment(coordinator.streamController)
            .environment(coordinator.shellBootstrapController)
            .environment(coordinator.achievementsController)
            .environment(coordinator.inputController)
            .environment(coordinator.settingsStore)
            .environment(coordinator.previewExportController)
    }
}

#Preview("AuthenticatedShellView", traits: .fixedLayout(width: 1920, height: 1080)) {
    AuthenticatedShellPreviewHost()
}
#endif
