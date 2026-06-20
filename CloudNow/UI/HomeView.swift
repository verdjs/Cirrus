import SwiftUI
import Combine
import CloudXCore
import CloudXModels

struct HomeView: View {
    let onPlay: (GameInfo) -> Void
    let onResume: (ResumableSession) -> Void

    @Environment(GamesViewModel.self) var viewModel
    @Environment(AuthManager.self) var authManager
    @Environment(SessionController.self) var sessionController
    @Environment(LibraryController.self) var libraryController
    @State private var tick = 0

    @FocusState private var focusedGameId: String?
    
    private var isXCloudSignedIn: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }

    private var isGFNSignedIn: Bool {
        authManager.isAuthenticated
    }

    private var homeGames: [GameInfo] {
        viewModel.libraryGames.isEmpty ? viewModel.mainGames : viewModel.libraryGames
    }

    private var xcloudItems: [CloudLibraryItem] {
        libraryController.sections.flatMap { $0.items }
    }
    
    private var featuredGames: [GameInfo] {
        Array(viewModel.mainGames.prefix(3))
    }
    
    private var backgroundUrl: String? {
        if let id = focusedGameId {
            if let game = viewModel.mainGames.first(where: { $0.id == id }) ?? viewModel.libraryGames.first(where: { $0.id == id }) {
                return game.heroBannerUrl ?? game.boxArtUrl
            }
            if let item = xcloudItems.first(where: { $0.id == id }) {
                return item.heroImageURL?.absoluteString ?? item.posterImageURL?.absoluteString
            }
        }
        return homeGames.first?.heroBannerUrl ?? homeGames.first?.boxArtUrl
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Immersive background
            ZStack {
                if let bgUrl = backgroundUrl, let url = URL(string: bgUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.black
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                    .id(bgUrl)
                }
                
                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.4), .black.opacity(0.95), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            
            if viewModel.isLoading && homeGames.isEmpty && xcloudItems.isEmpty {
                ProgressView().scaleEffect(2)
            } else if !isGFNSignedIn && !isXCloudSignedIn {
                VStack(spacing: 30) {
                    signInPromptRow(
                        service: "xCloud",
                        description: "Sign in to access your Xbox Game Pass library",
                        color: Color(red: 0.06, green: 0.49, blue: 0.06),
                        icon: "xbox.logo"
                    ) {
                        Task { await sessionController.beginSignIn() }
                    }
                    
                    signInPromptRow(
                        service: "GeForce NOW",
                        description: "Sign in to stream PC games",
                        color: Color(red: 0.46, green: 0.73, blue: 0.0),
                        icon: "play.tv.fill"
                    ) {
                        authManager.login()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Profile / Top Bar Mockup
                    HStack(alignment: .top) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                            VStack(alignment: .leading) {
                                Text("CloudNow User")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                HStack(spacing: 4) {
                                    Image(systemName: "g.circle.fill")
                                        .foregroundStyle(.gray)
                                    Text("21,337")
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 30) {
                            Image(systemName: "magnifyingglass")
                            Image(systemName: "gearshape")
                        }
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(.trailing, 40)
                        
                        Text(Date(), style: .time)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Middle Row (Recently Played / Home Games)
                    middleRow
                        .padding(.bottom, 40)
                    
                    // Bottom Row (Featured Tiles)
                    bottomRow
                }
                .padding(.bottom, 60)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if isGFNSignedIn {
                Task { await viewModel.refreshActiveSessions(authManager: authManager) }
            }
        }
    }
    
    private var middleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                if isGFNSignedIn && !homeGames.isEmpty {
                    ForEach(homeGames.indices, id: \.self) { index in
                        let game = homeGames[index]
                        Button { onPlay(game) } label: {
                            GameCardLabel(game: game)
                        }
                        .buttonStyle(.card)
                        .focused($focusedGameId, equals: game.id)
                        .frame(width: index == 0 ? 260 : 180)
                    }
                } else if isXCloudSignedIn && !xcloudItems.isEmpty {
                    ForEach(xcloudItems.indices, id: \.self) { index in
                        let item = xcloudItems[index]
                        XCloudGameCard(item: item)
                            .focused($focusedGameId, equals: item.id)
                            .frame(width: index == 0 ? 260 : 180)
                    }
                }
            }
            .padding(.horizontal, 60)
        }
        .scrollClipDisabled()
    }
    
    private var bottomRow: some View {
        HStack(spacing: 24) {
            // Tile 1: Browse your games
            Button {
                // Navigate to library - maybe we can't from here without a binding
            } label: {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.2, blue: 0.15), Color(red: 0.05, green: 0.1, blue: 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 16) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                        Text("Browse your games")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.card)
            .frame(width: 320, height: 200)
            .focused($focusedGameId, equals: "browse")
            
            // Featured games
            ForEach(featuredGames) { game in
                Button { onPlay(game) } label: {
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: URL(string: game.heroBannerUrl ?? game.boxArtUrl ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.3)
                            }
                        }
                        
                        LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .bottom, endPoint: .center)
                        
                        Text(game.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(20)
                    }
                }
                .buttonStyle(.card)
                .frame(width: 320, height: 200)
                .focused($focusedGameId, equals: game.id)
            }
        }
        .padding(.horizontal, 60)
    }

    private func signInPromptRow(service: String, description: String, color: Color, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to \(service)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.card)
        .padding(.horizontal, 60)
    }
}

// MARK: - xCloud Game Card
private struct XCloudGameCard: View {
    let item: CloudLibraryItem
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            // xCloud game launch — handled by the xCloud stack
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let imageUrl = item.posterImageURL ?? item.artURL {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(2/3, contentMode: .fill)
                        default:
                            xcloudCardPlaceholder
                        }
                    }
                } else {
                    xcloudCardPlaceholder
                }

                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(10)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .buttonStyle(.card)
        .focused($isFocused)
    }

    private var xcloudCardPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.06, green: 0.49, blue: 0.06).opacity(0.3))
            Image(systemName: "xbox.logo")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.4))
        }
        .aspectRatio(2/3, contentMode: .fit)
    }
}
