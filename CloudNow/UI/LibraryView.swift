import SwiftUI
import CloudXCore
import CloudXModels

private enum LibrarySortOrder: String, CaseIterable {
    case `default`   = "Default"
    case titleAZ     = "A → Z"
    case titleZA     = "Z → A"
    case recentFirst = "Recently Played"
}

private enum LibraryFilter: String, CaseIterable {
    case all       = "All"
    case xcloud    = "xCloud"
    case gfn       = "GeForce NOW"
}

struct LibraryView: View {
    let games: [GameInfo]
    let onPlay: (GameInfo) -> Void

    @Environment(GamesViewModel.self) var viewModel
    @Environment(AuthManager.self) var authManager
    @Environment(SessionController.self) var sessionController
    @Environment(LibraryController.self) var libraryController

    @State private var searchText = ""
    @State private var sortOrder: LibrarySortOrder = .default
    @State private var filter: LibraryFilter = .all

    /// Whether the user is signed into xCloud
    private var isXCloudSignedIn: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }

    /// Whether the user is signed into GeForce NOW
    private var isGFNSignedIn: Bool {
        authManager.isAuthenticated
    }

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 40)
    ]

    /// xCloud library items
    private var xcloudItems: [CloudLibraryItem] {
        libraryController.sections.flatMap { $0.items }
    }

    /// Filtered xCloud items based on search
    private var filteredXCloudItems: [CloudLibraryItem] {
        guard isXCloudSignedIn else { return [] }
        if searchText.isEmpty { return xcloudItems }
        return xcloudItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Filtered GFN games
    private var filteredGFNGames: [GameInfo] {
        guard isGFNSignedIn else { return [] }
        var result = searchText.isEmpty
            ? games
            : games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        switch sortOrder {
        case .default: break
        case .titleAZ: result.sort { $0.title < $1.title }
        case .titleZA: result.sort { $0.title > $1.title }
        case .recentFirst:
            let order = viewModel.recentlyPlayedIds
            result.sort {
                let li = order.firstIndex(of: $0.id) ?? Int.max
                let ri = order.firstIndex(of: $1.id) ?? Int.max
                return li < ri
            }
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !isXCloudSignedIn && !isGFNSignedIn {
                noServicesState
            } else if (games.isEmpty && xcloudItems.isEmpty) && viewModel.isLoading {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(0..<12, id: \.self) { _ in
                            GameCardSkeleton()
                        }
                    }
                    .padding(60)
                }
                .allowsHitTesting(false)
            } else {
                libraryContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Filter picker (only show if both services are signed in)
                    if isXCloudSignedIn && isGFNSignedIn {
                        Menu {
                            Picker("Filter", selection: $filter) {
                                ForEach(LibraryFilter.allCases, id: \.self) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search library")
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // === xCloud Library Section ===
                if isXCloudSignedIn && (filter == .all || filter == .xcloud) {
                    if !filteredXCloudItems.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 10) {
                                Text("xCloud Library")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                Image(systemName: "xbox.logo")
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.06, green: 0.49, blue: 0.06))
                                Text("\(filteredXCloudItems.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                            }
                            .padding(.horizontal, 60)

                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(filteredXCloudItems) { item in
                                    Button {
                                        // xCloud game launch handled by xCloud stack
                                    } label: {
                                        XCloudLibraryCardLabel(item: item)
                                    }
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .buttonStyle(.card)
                                }
                            }
                            .padding(.horizontal, 60)
                        }
                    } else if searchText.isEmpty {
                        xcloudEmptyLibrary
                    }
                } else if !isXCloudSignedIn && filter != .gfn {
                    signInPrompt(service: "xCloud", color: Color(red: 0.06, green: 0.49, blue: 0.06), icon: "xbox.logo")
                }

                // === GFN Library Section ===
                if isGFNSignedIn && (filter == .all || filter == .gfn) {
                    if !filteredGFNGames.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 10) {
                                Text("GeForce NOW Library")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                Image(systemName: "play.tv.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.46, green: 0.73, blue: 0.0))
                                Text("\(filteredGFNGames.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                            }
                            .padding(.horizontal, 60)

                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(filteredGFNGames) { game in
                                    Button {
                                        onPlay(viewModel.gameWithPreferredStore(game))
                                    } label: {
                                        GameCardLabel(game: game)
                                    }
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .buttonStyle(.card)
                                    .contextMenu {
                                        Button {
                                            viewModel.toggleFavorite(game.id)
                                        } label: {
                                            let isFav = viewModel.favoriteIds.contains(game.id)
                                            Label(
                                                isFav ? "Remove from Favorites" : "Add to Favorites",
                                                systemImage: isFav ? "star.slash.fill" : "star"
                                            )
                                        }
                                        if game.variants.count > 1 {
                                            Menu("Launch via...") {
                                                ForEach(game.variants, id: \.id) { variant in
                                                    Button {
                                                        viewModel.setPreferredStore(gameId: game.id, variantId: variant.id)
                                                    } label: {
                                                        let isSelected = viewModel.preferredVariantId(for: game) == variant.id
                                                        if isSelected {
                                                            Label(variant.storeName, systemImage: "checkmark")
                                                        } else {
                                                            Text(variant.storeName)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 60)
                        }
                    } else if searchText.isEmpty {
                        gfnEmptyLibrary
                    }
                } else if !isGFNSignedIn && filter != .xcloud {
                    signInPrompt(service: "GeForce NOW", color: Color(red: 0.46, green: 0.73, blue: 0.0), icon: "play.tv.fill")
                }
            }
            .padding(.vertical, 60)
        }
    }

    // MARK: - Empty / Prompt States

    private var noServicesState: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Services Connected")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Sign in to xCloud or GeForce NOW in Settings to see your library.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
    }

    private func signInPrompt(service: String, color: Color, icon: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in to \(service)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Go to Settings to connect your \(service) account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 60)
    }

    private var xcloudEmptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "xbox.logo")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Your xCloud library is empty")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var gfnEmptyLibrary: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Your GeForce NOW library is empty")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - xCloud Library Card Label

private struct XCloudLibraryCardLabel: View {
    let item: CloudLibraryItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageUrl = item.posterImageURL ?? item.artURL {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(2/3, contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
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

            // xCloud badge
            Image(systemName: "xbox.logo")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color(red: 0.06, green: 0.49, blue: 0.06).opacity(0.85), in: Circle())
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.06, green: 0.49, blue: 0.06).opacity(0.2))
            Image(systemName: "xbox.logo")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.3))
        }
        .aspectRatio(2/3, contentMode: .fit)
    }
}

// MARK: - Shared Box Art

struct GameBoxArt: View {
    let url: String?
    @State private var attempt = 0

    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            case .failure:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fit)
                    .shimmer()
                    .onAppear {
                        guard attempt < 3 else { return }
                        Task {
                            try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt)) * 0.5))
                            attempt += 1
                        }
                    }
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(2/3, contentMode: .fit)
                    .shimmer()
            @unknown default:
                Color.gray.opacity(0.2).aspectRatio(2/3, contentMode: .fit)
            }
        }
        .id(attempt)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Game Card Label (shared)

struct GameCardLabel: View {
    let game: GameInfo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameBoxArt(url: game.boxArtUrl)

            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(game.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(10)
        }
    }
}

// MARK: - Game Card (used on Home rows)

struct GameCardView: View {
    let game: GameInfo
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            GameCardLabel(game: game)
        }
        .buttonStyle(.card)
    }
}

// MARK: - Library Card

struct LibraryCardView: View {
    let game: GameInfo
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            GameCardLabel(game: game)
        }
        .buttonStyle(.card)
    }
}
