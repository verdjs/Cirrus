// CloudLibraryDetailHydrationView.swift
// Defines the cloud library detail hydration view used in the CloudLibrary / Detail surface.
//

import SwiftUI
import CloudXCore
import CloudXModels

struct CloudLibraryDetailHydrationView: View {
    let titleID: TitleID
    let originRoute: AppRoute
    let viewModel: CloudLibraryViewModel
    let onLaunchStream: (TitleID, String) -> Void
    var onSecondaryAction: (CloudLibraryActionViewState) -> Void = { _ in }

    @Environment(LibraryController.self) private var libraryController
    @Environment(AchievementsController.self) private var achievementsController
    @Environment(AuthManager.self) private var authManager
    @Environment(GamesViewModel.self) private var gamesViewModel

    @State private var refreshRequestID = 0
    @State private var showPlatformSelection = false
    @State private var matchedGFNGame: GameInfo? = nil

    var body: some View {
        Group {
            if let item = viewModel.cachedItemsByTitleID[titleID] {
                let inputSignature = detailInputSignature(for: item)
                let isHydrating = viewModel.detailHydrationInFlightTitleIDs.contains(titleID)
                let cachedDetailState = viewModel.detailStateCache.peek(titleID)?.state
                let shouldShowDetailLoading = cachedDetailState == nil && isHydrating
                ZStack {
                    if let cachedDetailState {
                        CloudLibraryTitleDetailScreen(
                            state: cachedDetailState,
                            onPrimaryAction: {
                                if authManager.isAuthenticated,
                                   let gfnGame = gamesViewModel.libraryGames.first(where: { normalizeTitle($0.title) == normalizeTitle(item.name) }) {
                                    matchedGFNGame = gfnGame
                                    showPlatformSelection = true
                                } else {
                                    onLaunchStream(item.typedTitleID, "detail_primary")
                                }
                            },
                            onSecondaryAction: onSecondaryAction,
                            showsAmbientBackground: false,
                            showsHeroArtwork: true,
                            usesOuterPadding: false,
                            interceptExitCommand: false
                        )
                        .equatable()
                        .transition(.opacity)
                    }
                    if shouldShowDetailLoading {
                        DetailRouteLoadingView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: shouldShowDetailLoading)
                .task(id: inputSignature) {
                    if let entry = viewModel.detailStateCache.peek(titleID),
                       entry.inputSignature == inputSignature {
                        return
                    }
                    await hydrateDetailViewState(for: item)
                }
            } else {
                CloudLibraryStatusPanel(
                    state: .init(
                        kind: .error,
                        title: "Couldn't open title",
                        message: "That game is no longer in the current catalog snapshot.",
                        primaryActionTitle: "Try Again"
                    ),
                    onPrimaryAction: requestLibraryRefresh
                )
            }
        }
        .confirmationDialog(
            "Choose Streaming Platform",
            isPresented: $showPlatformSelection,
            titleVisibility: .visible
        ) {
            Button("Xbox Cloud Gaming") {
                if let item = viewModel.cachedItemsByTitleID[titleID] {
                    onLaunchStream(item.typedTitleID, "detail_primary")
                }
            }
            Button("GeForce NOW") {
                if let gfnGame = matchedGFNGame {
                    gamesViewModel.activeGFNGame = gfnGame
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This game is available on both Xbox Cloud Gaming and GeForce NOW. Which service would you like to stream from?")
        }
        .task(id: refreshRequestID) {
            guard refreshRequestID > 0 else { return }
            await libraryController.refresh(forceRefresh: true, reason: .manualUser)
        }
    }

    // MARK: - Hydration

    private func hydrateDetailViewState(for item: CloudLibraryItem) async {
        await MainActor.run {
            _ = viewModel.detailHydrationInFlightTitleIDs.insert(titleID)
        }
        let startedAt = Date()
        async let detailTask: Void = libraryController.loadDetail(productID: item.typedProductID)
        async let achievementsTask: Void = achievementsController.loadTitleAchievements(titleID: item.typedTitleID)
        _ = await (detailTask, achievementsTask)
        let minimumLoadingDuration: TimeInterval = 0.25
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumLoadingDuration {
            let remaining = minimumLoadingDuration - elapsed
            let nanos = UInt64(max(0, remaining) * 1_000_000_000)
            try? await Task.sleep(for: .nanoseconds(nanos))
        }
        let snapshot = await MainActor.run { detailSnapshot(for: item) }
        await MainActor.run {
            _ = viewModel.detailHydrationInFlightTitleIDs.remove(titleID)
            viewModel.prewarmDetailState(titleID: titleID, snapshot: snapshot)
        }
    }

    private func requestLibraryRefresh() {
        refreshRequestID += 1
    }

    // MARK: - Cache key

    private func detailSnapshot(for item: CloudLibraryItem) -> CloudLibraryDataSource.DetailStateSnapshot {
        CloudLibraryDataSource.detailSnapshot(
            for: item,
            richDetail: libraryController.productDetail(productID: item.typedProductID),
            achievementSnapshot: achievementsController.titleAchievementSnapshot(titleID: item.typedTitleID),
            achievementErrorText: achievementsController.lastTitleAchievementsError(titleID: item.typedTitleID),
            isHydrating: false,
            previousBaseRoute: originRoute
        )
    }

    private func detailInputSignature(for item: CloudLibraryItem) -> String {
        viewModel.detailInputSignature(for: detailSnapshot(for: item))
    }

    private func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
