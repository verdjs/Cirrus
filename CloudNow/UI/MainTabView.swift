import SwiftUI
import CloudXCore

enum TabType: String, CaseIterable, Identifiable {
    case home
    case library
    case store
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .store: return "Store"
        case .settings: return "Settings"
        }
    }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "books.vertical.fill"
        case .store: return "bag.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum ShieldNowFocusTarget: Hashable {
    case account
    case tab(TabType)
}

struct MainTabView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(SessionController.self) var sessionController
    @Environment(LibraryController.self) var libraryController
    @Environment(SettingsStore.self) var settingsStore
    @State private var viewModel = GamesViewModel()
    @State private var gameToPlay: GameInfo?
    @State private var sessionToResume: ActiveSessionInfo? = nil
    @State private var directSessionToResume: SessionInfo? = nil

    @State private var selectedTab: TabType = .home
    @State private var isRailExpanded = false
    @FocusState private var focusedTarget: ShieldNowFocusTarget?

    /// Whether the user is signed into xCloud
    private var isXCloudSignedIn: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }

    /// Whether the user is signed into GeForce NOW
    private var isGFNSignedIn: Bool {
        authManager.isAuthenticated
    }

    var body: some View {
        HStack(spacing: 0) {
            // Side Rail Navigation Sidebar
            ZStack(alignment: .leading) {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .frame(width: isRailExpanded ? 320 : 92)
                
                VStack(alignment: .leading, spacing: 0) {
                    // Profile / Account section at the top
                    VStack(alignment: .leading, spacing: 14) {
                        Button {
                            // Focus can go to profile
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.06, green: 0.49, blue: 0.06), Color(red: 0.46, green: 0.73, blue: 0.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text("CX")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.black)
                            }
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: focusedTarget == .account ? 3 : 1)
                                    .padding(focusedTarget == .account ? -4 : 0)
                            )
                            .scaleEffect(focusedTarget == .account ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.12), value: focusedTarget)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedTarget, equals: .account)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 40)
                    
                    Spacer(minLength: 40)
                    
                    // Main navigation list
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(TabType.allCases) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: tab.systemImage)
                                        .font(.system(size: 22, weight: selectedTab == tab || focusedTarget == .tab(tab) ? .bold : .regular))
                                        .frame(width: 28, height: 28)
                                        .foregroundStyle(selectedTab == tab || focusedTarget == .tab(tab) ? Color(red: 0.06, green: 0.49, blue: 0.06) : Color.white.opacity(0.76))
                                    
                                    // Highlight line on the left side of active tab
                                    Rectangle()
                                        .fill(selectedTab == tab ? Color(red: 0.06, green: 0.49, blue: 0.06) : Color.clear)
                                        .frame(width: 3, height: 22)
                                    
                                    if isRailExpanded {
                                        Text(tab.title)
                                            .font(.system(size: 18, weight: selectedTab == tab || focusedTarget == .tab(tab) ? .bold : .regular, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundStyle(selectedTab == tab || focusedTarget == .tab(tab) ? Color.white : Color.white.opacity(0.82))
                                            .transition(.opacity)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(focusedTarget == .tab(tab) ? Color.white.opacity(0.12) : Color.clear)
                                )
                                .scaleEffect(focusedTarget == .tab(tab) ? 1.02 : 1.0)
                                .animation(.easeOut(duration: 0.12), value: focusedTarget)
                            }
                            .buttonStyle(.plain)
                            .focused($focusedTarget, equals: .tab(tab))
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
                .frame(width: isRailExpanded ? 320 : 92, alignment: .leading)
            }
            .frame(width: isRailExpanded ? 320 : 92)
            .focusSection()
            .onChange(of: focusedTarget) { _, target in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let target, target != .account && !isTabFocused(target) {
                        isRailExpanded = false
                    } else if target != nil {
                        isRailExpanded = true
                    } else {
                        isRailExpanded = false
                    }
                }
            }
            
            // Main Content Area
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        onPlay: { game in
                            directSessionToResume = nil
                            sessionToResume = viewModel.activeSessions.first { session in
                                game.variants.contains { v in
                                    guard let appId = v.appId, let sessionAppId = session.appId else { return false }
                                    return appId == sessionAppId
                                }
                            }
                            gameToPlay = game
                        },
                        onResume: { rs in
                            directSessionToResume = rs.session
                            sessionToResume = nil
                            gameToPlay = rs.game
                        }
                    )
                case .library:
                    LibraryView(games: viewModel.libraryGames, onPlay: { gameToPlay = $0 })
                case .store:
                    StoreView(games: viewModel.mainGames, onPlay: { gameToPlay = $0 })
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
        }
        .background(Color.black.ignoresSafeArea())
        .environment(viewModel)
        .task {
            if isGFNSignedIn {
                await viewModel.load(authManager: authManager)
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthed in
            if isAuthed {
                Task { await viewModel.load(authManager: authManager) }
            }
        }
        .onChange(of: viewModel.streamSettings) { viewModel.saveSettings() }
        .onChange(of: gameToPlay) { _, new in
            if new == nil {
                directSessionToResume = nil
                Task { await viewModel.refreshActiveSessions(authManager: authManager) }
            }
        }
        .fullScreenCover(item: $gameToPlay) { game in
            StreamView(
                game: game,
                settings: viewModel.streamSettings,
                existingSession: sessionToResume,
                directSession: directSessionToResume,
                onDismiss: {
                    gameToPlay = nil
                    sessionToResume = nil
                },
                onLeave: { leftGame, session in
                    viewModel.resumableSession = ResumableSession(
                        game: leftGame,
                        session: session,
                        leftAt: Date()
                    )
                }
            )
            .environment(authManager)
            .environment(viewModel)
        }
    }
    
    private func isTabFocused(_ target: ShieldNowFocusTarget) -> Bool {
        if case .tab = target { return true }
        return false
    }
}
