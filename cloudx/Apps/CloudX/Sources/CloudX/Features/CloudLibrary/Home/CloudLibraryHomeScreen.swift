// CloudLibraryHomeScreen.swift
// Defines the cloud library home screen for the CloudLibrary / Home surface.
//

import SwiftUI
import CloudXModels

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
    @State var focusSettler = FocusSettleDebouncer()
    @State var carouselIndex = 0
    @State private var scrollAnchorID: String?
    @State var pendingFocusTask: Task<Void, Never>?

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

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                scrollContentFadeBackground
                    .padding(.leading, CloudXTheme.Home.heroArtworkLeadingBleed)
                    .padding(.trailing, CloudXTheme.Home.heroArtworkTrailingBleed)

                LazyVStack(alignment: .leading, spacing: 0) {
                    heroSection

                    VStack(alignment: .leading, spacing: CloudXTheme.Home.sectionSpacing) {
                        if state.sections.isEmpty {
                            CloudLibraryStatusPanel(
                                state: .init(
                                    kind: .empty,
                                    title: "No featured rows yet",
                                    message: "Load your Game Pass library to populate Home rails.",
                                    primaryActionTitle: nil
                                )
                            )
                            .frame(height: 600)
                        } else {
                            ForEach(Array(state.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                                rail(section: section, sectionIndex: sectionIndex)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, -CloudXTheme.Home.heroRailOverlap)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .scrollPosition(id: $scrollAnchorID)
        .scrollIndicators(.hidden)
        .gamePassDisableSystemFocusEffect()
        .task(id: carouselIndex) {
            guard state.carouselItems.count > 1 else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            moveCarousel(by: 1)
        }
        .onAppear {
            logHomeScreenDebug("appear \(stateSummary())")
            syncCarouselIndexIfNeeded()
        }
        .onDisappear {
            focusSettler.cancel()
        }
        .onChange(of: state.carouselItems) { oldItems, newItems in
            logHomeScreenDebug(
                "carousel_items_changed old=\(oldItems.count) new=\(newItems.count) newSample=[\(carouselSample(newItems))]"
            )
            syncCarouselIndexIfNeeded()
        }
        .onChange(of: state.sections) { oldSections, newSections in
            logHomeScreenDebug(
                "rail_sections_changed old=\(oldSections.count) new=\(newSections.count) newSummary=[\(railSummary(newSections))]"
            )
        }
        .onChange(of: focusedTarget) { _, new in
            handleFocusedTargetChange(new)
        }
    }
}

#if DEBUG
#Preview("CloudLibraryHome Content", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .home,
        heroBackgroundURL: nil,
        contentHorizontalPadding: 0,
        contentLeadingAdjustment: -132,
        onSelectNav: { _ in }
    ) {
        CloudLibraryHomeScreen(
            state: CloudLibraryPreviewData.home,
            onSelectRailItem: { _ in },
            onSelectCarouselPlay: { _ in },
            onSelectCarouselDetails: { _ in }
        )
    }
}

#Preview("CloudLibraryHome Empty", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .home,
        heroBackgroundURL: nil,
        contentHorizontalPadding: 0,
        contentLeadingAdjustment: -132,
        onSelectNav: { _ in }
    ) {
        CloudLibraryHomeScreen(
            state: CloudLibraryPreviewData.homeEmpty,
            onSelectRailItem: { _ in },
            onSelectCarouselPlay: { _ in },
            onSelectCarouselDetails: { _ in }
        )
    }
}
#endif
