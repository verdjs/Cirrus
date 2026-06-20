// ConsoleListView.swift
// Defines the console inventory screen and the home-stream launch handoff into the stream surface.
//

import SwiftUI
import CloudXCore
import XCloudAPI

/// Renders the available remote-play consoles and owns the console-to-stream modal transition.
struct ConsoleListView: View {
    @Environment(ConsoleController.self) var consoleController
    @Environment(StreamController.self) var streamController
    var onRequestSideRailEntry: () -> Void = {}
    @State var showingStream = false
    @State var selectedConsole: RemoteConsole?
    @State var showTroubleshootDetails = false
    @FocusState var focusedTarget: ConsoleFocusTarget?
    @State var focusSettler = FocusSettleDebouncer()
    @State var pendingFocusTask: Task<Void, Never>?
    @State var lastFocusedConsoleID: String?
    @State var shouldRequestDeferredFocus = false

    struct RootShellVisibility: Equatable {
        let opacity: Double
        let allowsHitTesting: Bool
        let isAccessibilityHidden: Bool
    }

    init(
        onRequestSideRailEntry: @escaping () -> Void = {}
    ) {
        self.onRequestSideRailEntry = onRequestSideRailEntry
    }

    var body: some View {
        rootContent
            .opacity(shellVisibility.opacity)
            .allowsHitTesting(shellVisibility.allowsHitTesting)
            .accessibilityHidden(shellVisibility.isAccessibilityHidden)
            .fullScreenCover(isPresented: $showingStream, onDismiss: handleStreamDismissed) {
                if let console = selectedConsole {
                    StreamControllerInputHost(onOverlayToggle: {
                        streamController.requestOverlayToggle()
                    }, onMenuPress: {
                        streamController.requestMenuPress()
                    }) {
                        CloudXStreamView(context: .home(console: console))
                    }
                    .ignoresSafeArea()
                    .interactiveDismissDisabled(true)
                }
            }
    }

    private var shellVisibility: RootShellVisibility {
        Self.rootShellVisibility(isStreamPriorityModeActive: streamController.isStreamPriorityModeActive)
    }

    static func rootShellVisibility(isStreamPriorityModeActive: Bool) -> RootShellVisibility {
        if isStreamPriorityModeActive {
            return .init(
                opacity: 0,
                allowsHitTesting: false,
                isAccessibilityHidden: true
            )
        }
        return .init(
            opacity: 1,
            allowsHitTesting: true,
            isAccessibilityHidden: false
        )
    }

    private var rootContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("My Consoles")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.textPrimary)

                    Text(headerSubtitle)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.textSecondary)
                }

                HStack(spacing: 32) {
                    Label("Xbox on & remote play active", systemImage: "tv.fill")
                    Label("Instant-On/Sleep mode", systemImage: "bolt.fill")
                    Label("Low-latency network", systemImage: "wifi")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CloudXTheme.Colors.textSecondary)

                Divider()
                    .background(Color.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 20) {
                    if !consoleController.isLoading && !consoleController.consoles.isEmpty {
                        Text("AVAILABLE CONSOLES")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(CloudXTheme.Colors.textPrimary.opacity(0.6))
                            .padding(.leading, 8)
                    }

                    contentSection
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, CloudXTheme.Layout.outerPadding)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("route_consoles_root")
        .task { await refreshConsoles() }
        .onAppear {
            requestPrimaryFocus()
        }
        .onDisappear {
            focusSettler.cancel()
            pendingFocusTask?.cancel()
        }
        .onChange(of: focusedTarget) { _, target in
            handleFocusedTargetChange(target)
        }
        .onChange(of: consoleController.isLoading) { _, isLoading in
            guard !isLoading, shouldRequestDeferredFocus else { return }
            shouldRequestDeferredFocus = false
            requestPrimaryFocus()
        }
        .onChange(of: consoleIDs) { _, consoleIDs in
            handleConsoleIDsChange(consoleIDs)
        }
        .onMoveCommand { direction in
            NavigationPerformanceTracker.recordRemoteMoveStart(surface: "consoles", direction: direction)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if consoleController.isLoading {
            CloudLibraryStatusPanel(
                state: .init(
                    kind: .loading,
                    title: "Finding your Xbox",
                    message: "Checking your home consoles and remote play availability.",
                    primaryActionTitle: nil
                )
            )
        } else if consoleController.consoles.isEmpty {
            emptyState
        } else {
            consoleVerticalList
        }
    }

    private var consoleVerticalList: some View {
        VStack(spacing: 16) {
            ForEach(Array(consoleController.consoles.enumerated()), id: \.element.serverId) { index, console in
                Button {
                    launchHomeStream(console)
                } label: {
                    HStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(powerColor(for: console.powerState).opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: consoleIcon(for: console.consoleType))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(powerColor(for: console.powerState))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(console.deviceName)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))

                                if console.isDevKit {
                                    Text("DevKit")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.white.opacity(0.12)))
                                }
                            }

                            HStack(spacing: 12) {
                                Text(console.consoleType)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.secondary)

                                if console.outOfHomeWarning {
                                    Label("Out of home", systemImage: "house.slash.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.orange)
                                }
                                if console.wirelessWarning {
                                    Label("Wireless", systemImage: "wifi.exclamationmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.orange)
                                }
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(powerColor(for: console.powerState))
                                .frame(width: 8, height: 8)
                            Text(console.powerState.capitalized)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .focused($focusedTarget, equals: .console(console.serverId))
                .onMoveCommand { direction in
                    guard direction == .left else { return }
                    onRequestSideRailEntry()
                }
            }
        }
        .focusSection()
    }

    private func consoleIcon(for type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("series") {
            return "xbox.logo"
        }
        if lower.contains("one") {
            return "tv.fill"
        }
        return "gamecontroller.fill"
    }

    private func powerColor(for state: String) -> Color {
        switch state.lowercased() {
        case "on":
            return CloudXTheme.Colors.accent
        case "standby":
            return Color.orange
        default:
            return Color.white.opacity(0.55)
        }
    }

    var consoleIDs: [String] {
        consoleController.consoles.map(\.serverId)
    }

    private var headerSubtitle: String {
        if consoleController.isLoading {
            return "Syncing your remote play devices..."
        }
        let count = consoleController.consoles.count
        if count == 0 {
            return "No consoles detected yet. Make sure your Xbox is online and remote features are enabled."
        }
        return count == 1 ? "1 console ready for remote play." : "\(count) consoles ready for remote play."
    }

    func refreshConsoles() async {
        await consoleController.refresh()
    }

    func launchHomeStream(_ console: RemoteConsole) {
        Task { @MainActor in
            selectedConsole = await Self.prepareHomeStreamLaunch(
                console: console,
                isShowingStream: showingStream,
                enterPriorityMode: { context in
                    await streamController.enterStreamPriorityMode(context: context)
                }
            )
            guard selectedConsole != nil else { return }
            showingStream = true
        }
    }

    func handleStreamDismissed() {
        Task { @MainActor in
            selectedConsole = nil
            showingStream = false
            guard streamController.isStreamPriorityModeActive else {
                requestPrimaryFocus()
                return
            }
            await Self.restoreShellAfterStreamDismissal(
                stopStreaming: {
                    await streamController.stopStreaming()
                },
                exitPriorityMode: {
                    await streamController.exitStreamPriorityMode()
                },
                restoreFocus: {
                    requestPrimaryFocus()
                }
            )
        }
    }

    /// Enters stream-priority mode and returns the selected console when launch can proceed.
    static func prepareHomeStreamLaunch(
        console: RemoteConsole,
        isShowingStream: Bool,
        enterPriorityMode: (StreamRuntimeContext) async -> Void
    ) async -> RemoteConsole? {
        guard !isShowingStream else { return nil }
        await enterPriorityMode(.home(consoleId: console.serverId))
        return console
    }

    /// Stops streaming, exits priority mode, and restores focus to the console shell.
    static func restoreShellAfterStreamDismissal(
        stopStreaming: () async -> Void,
        exitPriorityMode: () async -> Void,
        restoreFocus: @MainActor () -> Void
    ) async {
        await stopStreaming()
        await exitPriorityMode()
        await MainActor.run {
            restoreFocus()
        }
    }
}

#if DEBUG
#Preview("ConsoleListView", traits: .fixedLayout(width: 1920, height: 1080)) {
    let coordinator = AppCoordinator()
    ZStack {
        CloudLibraryAmbientBackground(imageURL: nil)
        ConsoleListView()
            .environment(coordinator.consoleController)
            .environment(coordinator.streamController)
            .environment(coordinator.libraryController)
            .environment(coordinator.settingsStore)
    }
}
#endif
