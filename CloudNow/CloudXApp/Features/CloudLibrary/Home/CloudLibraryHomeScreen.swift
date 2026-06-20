// CloudLibraryHomeScreen.swift
// Defines the cloud library home screen for the CloudLibrary / Home surface.
//

import SwiftUI
import CloudXModels
import CloudXCore

struct CloudLibraryHomeScreen: View, Equatable {
    let state: CloudLibraryHomeViewState
    var preferredTitleID: TitleID? = nil
    let onSelectRailItem: (CloudLibraryHomeRailItemViewState) -> Void
    let onSelectCarouselPlay: (CloudLibraryHomeCarouselItemViewState) -> Void
    let onSelectCarouselDetails: (CloudLibraryHomeCarouselItemViewState) -> Void
    var onRequestSideRailEntry: () -> Void = {}
    var onFocusTileID: (TitleID?) -> Void = { _ in }
    var onSettledTileID: (TitleID?) -> Void = { _ in }
    var tileLookup: [TitleID: TileLookupEntry] = [:]
    var onSelectBrowseGames: () -> Void = {}

    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @FocusState var focusedTarget: HomeFocusTarget?
    @Namespace var heroButtonFocusNamespace
    @Namespace var homeContentFocusNamespace
    @State var focusSettler = FocusSettleDebouncer()
    @State var carouselIndex = 0
    @State private var scrollAnchorID: String?
    @State var pendingFocusTask: Task<Void, Never>?

    private var defaultFocusItemId: String? {
        if !isXboxSignedIn && !isGFNSignedIn {
            return "login_xbox"
        }
        if let firstXbox = state.sections.first?.items.first?.id {
            return firstXbox
        }
        return homeGames.first?.id
    }

    @Environment(AuthManager.self) private var authManager
    @Environment(GamesViewModel.self) private var gamesViewModel
    @Environment(SessionController.self) private var sessionController
    @Environment(ProfileController.self) private var profileController
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(LibraryController.self) private var libraryController

    @FocusState private var focusedItemId: String?

    var isXboxSignedIn: Bool {
        if case .authenticated(_) = sessionController.authState { return true }
        return false
    }

    var isGFNSignedIn: Bool {
        authManager.isAuthenticated
    }

    let tileFocusScale: CGFloat = CloudXTheme.Home.tileFocusScale
    let tileFocusBreathing: CGFloat = CloudXTheme.Home.tileFocusBreathing
    let railEdgeFocusInset: CGFloat = CloudXTheme.Home.railEdgeFocusInset
    let scrollFadeHeight: CGFloat = 220
    let carouselArtworkVerticalOffset: CGFloat = 100

    static func == (lhs: CloudLibraryHomeScreen, rhs: CloudLibraryHomeScreen) -> Bool {
        lhs.state == rhs.state &&
        lhs.preferredTitleID == rhs.preferredTitleID &&
        lhs.tileLookup == rhs.tileLookup
    }

    private var homeGames: [GameInfo] {
        gamesViewModel.libraryGames.isEmpty ? gamesViewModel.mainGames : gamesViewModel.libraryGames
    }

    private var featuredGames: [GameInfo] {
        Array(gamesViewModel.mainGames.prefix(3))
    }

    /// The URL we *want* to show — recomputed on every focus change.
    private var targetBackgroundUrl: String? {
        if let id = focusedItemId {
            // Check GFN games first
            if let game = gamesViewModel.mainGames.first(where: { $0.id == id }) ?? gamesViewModel.libraryGames.first(where: { $0.id == id }) {
                return game.heroBannerUrl ?? game.boxArtUrl
            }
            // Check Xbox games
            for section in state.sections {
                if let item = section.items.first(where: { $0.id == id }) {
                    if case .title(let titleItem) = item {
                        return titleItem.tile.artworkURL?.absoluteString
                    }
                }
            }
        }
        // Fallback to carousel / global hero
        if let url = currentCarouselItem?.heroBackgroundURL ?? state.heroBackgroundURL {
            return url.absoluteString
        }
        return homeGames.first?.heroBannerUrl ?? homeGames.first?.boxArtUrl
    }

    @State private var displayedBgUrl: String?
    @State private var bgDebounceTask: Task<Void, Never>?

    private var profileName: String {
        let snapshot = profileController.profileShellSnapshot()
        if let preferred = snapshot.preferredScreenName?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
            return preferred
        }
        return settingsStore.shell.profileName
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Immersive Background — custom crossfading wrapper
            CrossfadingBackground(url: displayedBgUrl.flatMap { URL(string: $0) })
                .ignoresSafeArea()
                .onChange(of: targetBackgroundUrl) { _, newValue in
                    bgDebounceTask?.cancel()
                    bgDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        displayedBgUrl = newValue
                    }
                }
                .onAppear {
                    displayedBgUrl = targetBackgroundUrl
                }

            // Top overlay gradient
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.65), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Spacer to push the top row down to the lower part of the screen
                    Color.clear.frame(height: 460)

                    // ── Xbox Cloud Library Row ──
                    if !state.sections.isEmpty || libraryController.isLoading {
                        HStack(spacing: 12) {
                            Text("Xbox")
                                .font(CloudXTheme.Fonts.sectionTitle)
                                .foregroundStyle(.white)
                            
                            if libraryController.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 60)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 24) {
                                if !state.sections.isEmpty {
                                    ForEach(Array(state.sections.first!.items.prefix(10))) { item in
                                        Button {
                                            onSelectRailItem(item)
                                        } label: {
                                            Group {
                                                if case .title(let titleItem) = item, let url = titleItem.tile.artworkURL {
                                                    CachedRemoteImage(url: url, kind: .hero, maxPixelSize: 600) {
                                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                            .fill(CloudXTheme.Colors.glassFill)
                                                    }
                                                } else {
                                                    RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                        .fill(CloudXTheme.Colors.glassFill)
                                                }
                                            }
                                            .aspectRatio(1, contentMode: .fit)
                                            .frame(height: 270)
                                            .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.md))
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedItemId, equals: item.id)
                                        .prefersDefaultFocus(item.id == defaultFocusItemId, in: homeContentFocusNamespace)
                                    }
                                } else {
                                    ForEach(0..<6, id: \.self) { idx in
                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                            .fill(CloudXTheme.Colors.glassFill)
                                            .opacity(0.15)
                                            .aspectRatio(1, contentMode: .fit)
                                            .frame(height: 270)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 60)
                            .padding(.vertical, 16)
                        }
                        .frame(height: 310)
                    }

                    // ── GeForce NOW Library Row ──
                    if !homeGames.isEmpty || gamesViewModel.isLoading {
                        HStack(spacing: 12) {
                            Text("GeForce NOW")
                                .font(CloudXTheme.Fonts.sectionTitle)
                                .foregroundStyle(.white)
                            
                            if gamesViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 24) {
                                if !homeGames.isEmpty {
                                    ForEach(homeGames, id: \.id) { game in
                                        Button {
                                            gamesViewModel.activeGFNGame = game
                                        } label: {
                                            ZStack(alignment: .bottomLeading) {
                                                Group {
                                                    if let artUrl = game.boxArtUrl, let url = URL(string: artUrl) {
                                                        CachedRemoteImage(url: url, kind: .hero, maxPixelSize: 600) {
                                                            RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                                .fill(CloudXTheme.Colors.glassFill)
                                                        }
                                                    } else {
                                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                            .fill(CloudXTheme.Colors.glassFill)
                                                    }
                                                }

                                                if focusedItemId == game.id {
                                                    LinearGradient(
                                                        colors: [.black.opacity(0.85), .clear],
                                                        startPoint: .bottom,
                                                        endPoint: .center
                                                    )
                                                    Text(game.title)
                                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(2)
                                                        .padding(16)
                                                }
                                            }
                                            .aspectRatio(1, contentMode: .fit)
                                            .frame(height: 270)
                                            .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.md))
                                        }
                                        .buttonStyle(.card)
                                        .focused($focusedItemId, equals: game.id)
                                        .prefersDefaultFocus(game.id == defaultFocusItemId, in: homeContentFocusNamespace)
                                    }
                                } else {
                                    ForEach(0..<6, id: \.self) { idx in
                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                            .fill(CloudXTheme.Colors.glassFill)
                                            .opacity(0.15)
                                            .aspectRatio(1, contentMode: .fit)
                                            .frame(height: 270)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CloudXTheme.Radius.md)
                                                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 60)
                            .padding(.vertical, 16)
                        }
                        .frame(height: 310)
                    }

                    // ── Connect Accounts (Login Buttons) ──
                    if !isXboxSignedIn && !isGFNSignedIn {
                        Text("Connect your accounts")
                            .font(CloudXTheme.Fonts.sectionTitle)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 60)
                            .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 30) {
                                Button {
                                    Task { await sessionController.beginSignIn() }
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.05, green: 0.18, blue: 0.06).opacity(0.85),
                                                Color(red: 0.02, green: 0.08, blue: 0.02).opacity(0.95)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg)
                                            .fill(CloudXTheme.Colors.glassFill)

                                        VStack(alignment: .leading, spacing: 0) {
                                            Spacer()
                                            Image(systemName: "xbox.logo")
                                                .font(.system(size: 72, weight: .light))
                                                .foregroundStyle(Color(red: 0.06, green: 0.8, blue: 0.06))
                                            Spacer()
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Sign In to Xbox")
                                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                Text("Stream your Xbox Cloud Gaming library")
                                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Color.white.opacity(0.7))
                                            }
                                        }
                                        .padding(32)
                                    }
                                    .frame(width: 560, height: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg))
                                }
                                .buttonStyle(.card)
                                .focused($focusedItemId, equals: "login_xbox")

                                Button {
                                    authManager.login()
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.35, green: 0.55, blue: 0.0).opacity(0.85),
                                                Color(red: 0.15, green: 0.25, blue: 0.0).opacity(0.95)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg)
                                            .fill(CloudXTheme.Colors.glassFill)

                                        VStack(alignment: .leading, spacing: 0) {
                                            Spacer()
                                            Image(systemName: "play.tv.fill")
                                                .font(.system(size: 72, weight: .light))
                                                .foregroundStyle(Color(red: 0.46, green: 0.73, blue: 0.0))
                                            Spacer()
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Sign In to GeForce NOW")
                                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                                Text("Stream your Steam and GFN games")
                                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Color.white.opacity(0.7))
                                            }
                                        }
                                        .padding(32)
                                    }
                                    .frame(width: 560, height: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg))
                                }
                                .buttonStyle(.card)
                                .focused($focusedItemId, equals: "login_gfn")
                            }
                            .padding(.horizontal, 60)
                            .padding(.vertical, 16)
                        }
                        .frame(height: 340)
                    }

                    // ── Featured Bottom Row ──
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 30) {
                            // Browse your games tile
                            Button {
                                onSelectBrowseGames()
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.12, green: 0.16, blue: 0.22),
                                            Color(red: 0.06, green: 0.08, blue: 0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg)
                                        .fill(CloudXTheme.Colors.glassFill)

                                    VStack(alignment: .leading, spacing: 0) {
                                        Spacer()
                                        Image(systemName: "gamecontroller.fill")
                                            .font(.system(size: 72, weight: .light))
                                            .foregroundStyle(CloudXTheme.Colors.textSecondary)
                                        Spacer()
                                        Text("Browse your games")
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(32)
                                }
                                .frame(width: 560, height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg))
                            }
                            .buttonStyle(.card)
                            .focused($focusedItemId, equals: "browse")

                            // Featured game tiles
                            ForEach(featuredGames) { game in
                                Button {
                                    gamesViewModel.activeGFNGame = game
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        Group {
                                            if let artUrl = game.heroBannerUrl ?? game.boxArtUrl, let url = URL(string: artUrl) {
                                                CachedRemoteImage(url: url, kind: .hero, maxPixelSize: 1200) {
                                                    RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg)
                                                        .fill(CloudXTheme.Colors.glassFill)
                                                }
                                            } else {
                                                RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg)
                                                    .fill(CloudXTheme.Colors.glassFill)
                                            }
                                        }
                                        .clipped()

                                        LinearGradient(
                                            colors: [.black.opacity(0.9), .clear],
                                            startPoint: .bottom,
                                            endPoint: .center
                                        )

                                        Text(game.title)
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .padding(32)
                                    }
                                    .frame(width: 560, height: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: CloudXTheme.Radius.lg))
                                }
                                .buttonStyle(.card)
                                .focused($focusedItemId, equals: game.id)
                                .prefersDefaultFocus(game.id == defaultFocusItemId, in: homeContentFocusNamespace)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 16)
                    }
                    .frame(height: 340)
                    
                    // Bottom padding inside scrollview
                    Color.clear.frame(height: 60)
                }
            }
            .focusSection()
            .focusScope(homeContentFocusNamespace)
        }
        .onAppear {
            syncCarouselIndexIfNeeded()
        }
        .task(id: defaultFocusItemId) {
            if focusedItemId == nil, let defaultID = defaultFocusItemId {
                focusedItemId = defaultID
            }
        }
        .task(id: carouselIndex) {
            guard state.carouselItems.count > 1 else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            moveCarousel(by: 1)
        }
    }
}

/// A robust full-screen container that crossfades between two background images
/// with a premium, smooth Ken Burns zoom transition and zero layout pops.
struct CrossfadingBackground: View {
    let url: URL?

    @State private var activeURL: URL?
    @State private var previousURL: URL?
    @State private var opacity: Double = 0.0
    @State private var scale: CGFloat = 1.05

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // Old background remains at full opacity underneath
                if let prev = previousURL {
                    CachedRemoteImage(
                        url: prev,
                        kind: .hero,
                        maxPixelSize: 1920,
                        placeholder: { Color.black }
                    )
                    .id(prev)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }

                // New background slowly fades in and zooms out/in (Ken Burns)
                if let active = activeURL {
                    CachedRemoteImage(
                        url: active,
                        kind: .hero,
                        maxPixelSize: 1920,
                        onImageLoaded: {
                            // Reset zoom scale start state
                            scale = 1.08
                            // Snappy, cinematic easeOut transition for both opacity and zoom scale
                            withAnimation(.easeOut(duration: 0.35)) {
                                opacity = 1.0
                                scale = 1.02 // Gentle zoom settle
                            }
                        },
                        placeholder: { Color.clear }
                    )
                    .id(active)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .clipped()
                    .opacity(opacity)
                }
            }
        }
        .onChange(of: url) { _, newURL in
            if newURL != activeURL {
                previousURL = activeURL
                activeURL = newURL
                opacity = 0.0
                scale = 1.08
                if newURL == nil {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        opacity = 1.0
                        scale = 1.0
                    }
                }
            }
        }
        .onAppear {
            activeURL = url
            opacity = 1.0
            scale = 1.02
        }
    }
}

