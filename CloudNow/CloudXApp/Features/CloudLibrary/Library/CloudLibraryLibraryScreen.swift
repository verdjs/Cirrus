// CloudLibraryLibraryScreen.swift
// Defines the cloud library library screen for the CloudLibrary / Library surface.
//

import SwiftUI
import CloudXModels

struct CloudLibraryLibraryScreen: View, Equatable {

    let state: CloudLibraryLibraryViewState
    let tileLookup: [TitleID: MediaTileViewState]
    var preferredTitleID: TitleID? = nil
    let searchText: Binding<String>
    let onSelectTile: (MediaTileViewState) -> Void
    var onFocusTileID: (TitleID?) -> Void = { _ in }
    var onSettledTileID: (TitleID?) -> Void = { _ in }
    var onSelectTab: (String) -> Void = { _ in }
    var onSelectFilter: (ChipViewState) -> Void = { _ in }
    var onSelectSort: () -> Void = {}
    var onClearFilters: () -> Void = {}
    var onRequestSideRailEntry: () -> Void = {}

    @Environment(AuthManager.self) private var authManager
    @Environment(GamesViewModel.self) private var gamesViewModel

    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Namespace var gridFocusNamespace
    enum LibraryFocusTarget: Hashable {
        case tab(String)
        case headerButton(String)
        case filter(String)
        case tile(TitleID)
    }

    @FocusState var focusedTarget: LibraryFocusTarget?
    @State var lastFocusedGridTitleID: TitleID?
    @State var lastFocusedHeaderTarget: LibraryFocusTarget?
    // Static column mapping is used directly to avoid layout invalidation cycles.
    @State var focusSettler = FocusSettleDebouncer()
    @State var pendingFocusTask: Task<Void, Never>?

    let gridItemWidth = CloudXTheme.Library.gridItemWidth
    let gridItemSpacing = CloudXTheme.Library.gridItemSpacing
    let gridEdgeFocusInset = CloudXTheme.Library.gridEdgeFocusInset
    static let headerAnchorID = "library_header"
    static let defaultGridColumnCount: Int = {
        let availableWidth = max(1920 - (CloudXTheme.Library.gridEdgeFocusInset * 2), CloudXTheme.Library.gridItemWidth)
        return max(Int((availableWidth + CloudXTheme.Library.gridItemSpacing) / (CloudXTheme.Library.gridItemWidth + CloudXTheme.Library.gridItemSpacing)), 1)
    }()
    static let defaultColumns: [GridItem] = Array(
        repeating: GridItem(.fixed(CloudXTheme.Library.gridItemWidth), spacing: CloudXTheme.Library.gridItemSpacing, alignment: .top),
        count: defaultGridColumnCount
    )

    enum LibraryGridItem: Identifiable, Hashable {
        case xbox(MediaTileViewState)
        case gfn(GameInfo)
        case dual(xbox: MediaTileViewState, gfn: GameInfo)
        
        var id: String {
            switch self {
            case .xbox(let item): return "xbox-\(item.id)"
            case .gfn(let game): return "gfn-\(game.id)"
            case .dual(let item, let game): return "dual-\(item.id)-\(game.id)"
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: LibraryGridItem, rhs: LibraryGridItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    private func normalizeTitle(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Returns true when every word in `query` appears as a consecutive (contiguous)
    /// substring within `title`, case-insensitively.
    private func matchesSearch(_ title: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lowerTitle = title.lowercased()
        let words = query.lowercased().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return words.allSatisfy { lowerTitle.contains($0) }
    }

    var combinedItems: [LibraryGridItem] {
        let query = searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Xbox items are already filtered by the data source (state.gridItems),
        // but if there’s a live search query apply our consecutive-word matching.
        let xboxItems: [MediaTileViewState]
        if query.isEmpty {
            xboxItems = state.gridItems
        } else {
            xboxItems = state.gridItems.filter { matchesSearch($0.title, query: query) }
        }

        var gfnItems: [GameInfo] = []
        if authManager.isAuthenticated {
            let gfnSource = gamesViewModel.libraryGames
            gfnItems = query.isEmpty ? gfnSource : gfnSource.filter { matchesSearch($0.title, query: query) }
        }
        
        var gfnMap: [String: GameInfo] = [:]
        gfnMap.reserveCapacity(gfnItems.count)
        for game in gfnItems {
            gfnMap[normalizeTitle(game.title)] = game
        }
        
        var items: [LibraryGridItem] = []
        items.reserveCapacity(xboxItems.count + gfnItems.count)
        
        var matchedGfnIds = Set<String>()
        matchedGfnIds.reserveCapacity(gfnItems.count)
        
        for xboxItem in xboxItems {
            let normXbox = normalizeTitle(xboxItem.title)
            if let gfnGame = gfnMap[normXbox] {
                items.append(.dual(xbox: xboxItem, gfn: gfnGame))
                matchedGfnIds.insert(gfnGame.id)
            } else {
                items.append(.xbox(xboxItem))
            }
        }
        
        for game in gfnItems {
            if !matchedGfnIds.contains(game.id) {
                items.append(.gfn(game))
            }
        }
        
        return items
    }

    private func tileState(for item: LibraryGridItem) -> MediaTileViewState {
        switch item {
        case .xbox(let tileItem):
            return tileItem
        case .gfn(let game):
            let artworkURL = game.boxArtUrl.flatMap { URL(string: $0) }
            return MediaTileViewState(
                id: game.id,
                titleID: TitleID(rawValue: game.id),
                title: game.title,
                subtitle: game.variants.first?.storeName ?? "PC",
                artworkURL: artworkURL,
                badgeText: "GeForce NOW"
            )
        case .dual(let tileItem, _):
            return MediaTileViewState(
                id: tileItem.id,
                titleID: tileItem.titleID,
                title: tileItem.title,
                subtitle: tileItem.subtitle,
                caption: tileItem.caption,
                artworkURL: tileItem.artworkURL,
                badgeText: "Xbox & GFN",
                aspect: tileItem.aspect
            )
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CloudXTheme.Library.sectionSpacing) {
                    header(scrollProxy: scrollProxy)

                    if combinedItems.isEmpty {
                        CloudLibraryStatusPanel(
                            state: .init(
                                kind: .empty,
                                title: "Library is empty",
                                message: "Once cloud titles are available they will appear here.",
                                primaryActionTitle: nil
                            )
                        )
                        .frame(height: 480)
                    } else {
                        LazyVGrid(columns: Self.defaultColumns, alignment: .leading, spacing: CloudXTheme.Library.gridItemSpacing) {
                            ForEach(Array(combinedItems.enumerated()), id: \.element.id) { index, item in
                                let tileItem = tileState(for: item)
                                MediaTileView(
                                    state: tileItem,
                                    onSelect: {
                                        switch item {
                                        case .xbox(let xboxItem):
                                            onSelectTile(xboxItem)
                                        case .gfn(let game):
                                            gamesViewModel.activeGFNGame = game
                                        case .dual(let xboxItem, _):
                                            onSelectTile(xboxItem)
                                        }
                                    },
                                    forcedFocus: focusedTarget == .tile(tileItem.titleID)
                                )
                                .equatable()
                                .focused($focusedTarget, equals: .tile(tileItem.titleID))
                                .prefersDefaultFocus(tileItem.id == defaultGridFocusTileID, in: gridFocusNamespace)
                                .onMoveCommand { direction in
                                    NavigationPerformanceTracker.recordRemoteMoveStart(surface: "library", direction: direction)
                                    recordMediaTileMoveDirection(direction)
                                    if direction == .left, isLeadingGridColumn(index: index) {
                                        onRequestSideRailEntry()
                                    } else if direction == .up, isTopGridRow(index: index) {
                                        requestHeaderFocusFromSideRail(scrollProxy: scrollProxy)
                                    }
                                }
                                .id(tileItem.id)
                            }
                        }
                        .accessibilityIdentifier("library_grid_container")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusScope(gridFocusNamespace)
                        .focusSection()
                        .padding(.horizontal, gridEdgeFocusInset)
                        .padding(.bottom, 0)
                    }
                }
                .padding(.top, 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("route_library_root")
            .scrollIndicators(.hidden)
            .gamePassDisableSystemFocusEffect()
            .onChange(of: focusedTarget) { _, target in
                guard let target else {
                    onFocusTileID(nil)
                    onSettledTileID(nil)
                    focusSettler.cancel()
                    NavigationPerformanceTracker.recordFocusLoss(surface: "library")
                    return
                }

                switch target {
                case .tile(let titleID):
                    lastFocusedGridTitleID = titleID
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: titleID.rawValue)
                    onFocusTileID(titleID)
                    scheduleFocusSettled(targetLabel: titleID.rawValue, settledTitleID: titleID)
                case .tab(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "tab:\(id)")
                    scheduleFocusSettled(targetLabel: "tab:\(id)", settledTitleID: nil)
                    // Immediately pin scroll to top so the grid doesn't fight back.
                    withAnimation(nil) { scrollProxy.scrollTo(Self.headerAnchorID, anchor: .top) }
                case .headerButton(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "header:\(id)")
                    scheduleFocusSettled(targetLabel: "header:\(id)", settledTitleID: nil)
                    withAnimation(nil) { scrollProxy.scrollTo(Self.headerAnchorID, anchor: .top) }
                case .filter(let id):
                    lastFocusedHeaderTarget = target
                    onFocusTileID(nil)
                    NavigationPerformanceTracker.recordFocusTarget(surface: "library", target: "filter:\(id)")
                    scheduleFocusSettled(targetLabel: "filter:\(id)", settledTitleID: nil)
                    withAnimation(nil) { scrollProxy.scrollTo(Self.headerAnchorID, anchor: .top) }
                }
            }
            .onChange(of: state.sortLabel) { _, _ in
                // Grid reorders on sort — remembered position is no longer valid.
                lastFocusedGridTitleID = nil
            }
            .onChange(of: state.selectedTabID) { _, _ in
                // Tab switch changes which items are visible — reset grid focus.
                lastFocusedGridTitleID = nil
            }

            // Removed GeometryReader to eliminate focus and scrolling lag on legacy Apple TV GPUs.
        }
        .onDisappear {
            focusSettler.cancel()
        }
    }

    static func == (lhs: CloudLibraryLibraryScreen, rhs: CloudLibraryLibraryScreen) -> Bool {
        lhs.state == rhs.state &&
        lhs.tileLookup == rhs.tileLookup &&
        lhs.preferredTitleID == rhs.preferredTitleID &&
        lhs.searchText.wrappedValue == rhs.searchText.wrappedValue
    }
}

#if DEBUG
#Preview("CloudLibraryLibrary Grid", traits: .fixedLayout(width: 1920, height: 1080)) {
        CloudLibraryShellView(
            sideRail: CloudLibraryPreviewData.sideRail,
            selectedNavID: .library,
            heroBackgroundURL: CloudLibraryPreviewData.library.heroBackdropURL,
            onSelectNav: { _ in }
        ) {
            let tileLookup: [TitleID: MediaTileViewState] = Dictionary(
                uniqueKeysWithValues: CloudLibraryPreviewData.library.gridItems.map {
                    ($0.titleID, $0)
                }
            )
            CloudLibraryLibraryScreen(
                state: CloudLibraryPreviewData.library,
                tileLookup: tileLookup,
                searchText: .constant(""),
                onSelectTile: { _ in }
            )
        }
}
#endif
