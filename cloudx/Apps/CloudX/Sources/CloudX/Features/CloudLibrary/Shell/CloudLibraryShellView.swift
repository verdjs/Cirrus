// CloudLibraryShellView.swift
// Defines the cloud library shell view used in the CloudLibrary / Shell surface.
//

import SwiftUI

struct CloudLibraryShellView<Content: View>: View {
    let sideRail: SideRailNavigationViewState
    let selectedNavID: SideRailNavID
    let activeUtilityRoute: ShellUtilityRoute?
    let heroBackgroundURL: URL?
    let contentTopPadding: CGFloat
    let contentHorizontalPadding: CGFloat
    let contentLeadingAdjustment: CGFloat
    let contentBottomPadding: CGFloat
    let sideRailSurfaceID: String
    let onSelectNav: (SideRailNavID) -> Void
    var onSelectSideRailAction: (String) -> Void = { _ in }
    var onMoveFromSideRailToContent: (() -> Void)? = nil
    var isSideRailExpanded: Binding<Bool> = .constant(false)
    var forceCollapsedSideRail: Bool = false
    var collapsedSelectedNavFocusable: Bool = true
    var onExpansionChanged: ((Bool) -> Void)? = nil
    let content: () -> Content

    init(
        sideRail: SideRailNavigationViewState,
        selectedNavID: SideRailNavID,
        activeUtilityRoute: ShellUtilityRoute? = nil,
        heroBackgroundURL: URL?,
        contentTopPadding: CGFloat = CloudXTheme.Shell.contentTopPadding,
        contentHorizontalPadding: CGFloat = CloudXTheme.Layout.outerPadding,
        contentLeadingAdjustment: CGFloat = 0,
        contentBottomPadding: CGFloat = 18,
        sideRailSurfaceID: String = "game_pass",
        onSelectNav: @escaping (SideRailNavID) -> Void,
        onSelectSideRailAction: @escaping (String) -> Void = { _ in },
        onMoveFromSideRailToContent: (() -> Void)? = nil,
        isSideRailExpanded: Binding<Bool> = .constant(false),
        forceCollapsedSideRail: Bool = false,
        collapsedSelectedNavFocusable: Bool = true,
        onExpansionChanged: ((Bool) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.sideRail = sideRail
        self.selectedNavID = selectedNavID
        self.activeUtilityRoute = activeUtilityRoute
        self.heroBackgroundURL = heroBackgroundURL
        self.contentTopPadding = contentTopPadding
        self.contentHorizontalPadding = contentHorizontalPadding
        self.contentLeadingAdjustment = contentLeadingAdjustment
        self.contentBottomPadding = contentBottomPadding
        self.sideRailSurfaceID = sideRailSurfaceID
        self.onSelectNav = onSelectNav
        self.onSelectSideRailAction = onSelectSideRailAction
        self.onMoveFromSideRailToContent = onMoveFromSideRailToContent
        self.isSideRailExpanded = isSideRailExpanded
        self.forceCollapsedSideRail = forceCollapsedSideRail
        self.collapsedSelectedNavFocusable = collapsedSelectedNavFocusable
        self.onExpansionChanged = onExpansionChanged
        self.content = content
    }

    var body: some View {
        let railInsetLeading = CloudXTheme.Shell.sideRailInsetLeading
        let contentLeadingInset = CloudXTheme.Shell.contentLeadingInset + contentLeadingAdjustment

        ZStack(alignment: .top) {
            CloudLibraryAmbientBackground(imageURL: heroBackgroundURL)
            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: Color.black.opacity(0.07), location: 0.56),
                    .init(color: CloudXTheme.Colors.bgBottom.opacity(0.64), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            content()
                .padding(.top, contentTopPadding)
                .padding(.leading, contentLeadingInset)
                .padding(.trailing, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SideRailNavigationView(
                state: sideRail,
                selectedNavID: selectedNavID,
                activeUtilityRoute: activeUtilityRoute,
                onSelectNav: onSelectNav,
                onSelectAction: onSelectSideRailAction,
                onMoveFromSideRailToContent: onMoveFromSideRailToContent,
                surfaceID: sideRailSurfaceID,
                isExpanded: isSideRailExpanded,
                onExpansionChanged: onExpansionChanged,
                forceCollapsed: forceCollapsedSideRail,
                collapsedSelectedNavFocusable: collapsedSelectedNavFocusable
            )
            .padding(.top, CloudXTheme.Shell.sideRailTopPadding)
            .padding(.bottom, CloudXTheme.Shell.sideRailBottomPadding)
            .padding(.leading, railInsetLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CloudLibraryStatusPanel: View {
    let state: CloudLibraryStatusViewState
    var onPrimaryAction: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isPrimaryActionFocused: Bool

    var body: some View {
        VStack {
            Spacer()

            GlassCard(cornerRadius: CloudXTheme.Radius.xl, fill: Color.black.opacity(0.38), stroke: Color.white.opacity(0.12), shadowOpacity: 0.28) {
                VStack(spacing: 18) {
                    icon
                    Text(state.title)
                        .font(CloudXTypography.rounded(34, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(CloudXTheme.Colors.textPrimary)

                    Text(state.message)
                        .font(CloudXTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(CloudXTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)

                    if let title = state.primaryActionTitle, let onPrimaryAction {
                        Button(action: onPrimaryAction) {
                            FocusAwareView { isFocused in
                                CloudLibraryActionButton(
                                    action: .init(id: "primary", title: title, systemImage: "arrow.clockwise", style: .primary),
                                    isFocused: isFocused
                                )
                                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 24)
                            }
                        }
                        .focused($isPrimaryActionFocused)
                        .defaultFocus($isPrimaryActionFocused, true)
                        .buttonStyle(CloudLibraryTVButtonStyle())
                        .gamePassDisableSystemFocusEffect()
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 34)
                .frame(maxWidth: 920)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var icon: some View {
        switch state.kind {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(CloudXTheme.Colors.focusTint)
                .scaleEffect(1.4)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54))
                .foregroundStyle(CloudXTheme.Colors.warning)
        case .empty:
            Image(systemName: "cloud.fill")
                .font(.system(size: 54))
                .foregroundStyle(CloudXTheme.Colors.textMuted)
        }
    }
}

#if DEBUG
#Preview("Loading", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .home,
        heroBackgroundURL: CloudLibraryPreviewData.home.heroBackgroundURL,
        onSelectNav: { _ in }
    ) {
        CloudLibraryStatusPanel(state: CloudLibraryPreviewData.statusLoading)
    }
}

#Preview("Error", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .home,
        heroBackgroundURL: CloudLibraryPreviewData.home.heroBackgroundURL,
        onSelectNav: { _ in }
    ) {
        CloudLibraryStatusPanel(state: CloudLibraryPreviewData.statusError)
    }
}

#Preview("Empty", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryShellView(
        sideRail: CloudLibraryPreviewData.sideRail,
        selectedNavID: .library,
        heroBackgroundURL: CloudLibraryPreviewData.library.heroBackdropURL,
        onSelectNav: { _ in }
    ) {
        CloudLibraryStatusPanel(state: CloudLibraryPreviewData.statusEmpty)
    }
}
#endif
