// CloudLibraryShellView.swift
// Defines the cloud library shell view used in the CloudLibrary / Shell surface.
//

import SwiftUI
import CloudXCore
import XCloudAPI

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

    enum TopBarFocusTarget: Hashable {
        case profile
        case nav(SideRailNavID)
        case settings
    }
    @Environment(SessionController.self) private var sessionController
    @Environment(AuthManager.self) private var authManager
    @Environment(ShellBootstrapController.self) private var shellBootstrapController
    @Environment(GamesViewModel.self) private var gamesViewModel
    @FocusState private var focusedTopBarItem: TopBarFocusTarget?
    @State private var isHeaderLight = false


    private var isXboxAuthenticated: Bool {
        if case .authenticated = sessionController.authState { return true }
        return false
    }

    var body: some View {
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
                .padding(.top, selectedNavID == .home ? 0 : contentTopPadding + 90)
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()

            // Top Navigation Bar
            HStack(alignment: .center, spacing: 0) {
                if isXboxAuthenticated {
                    Button {
                        onSelectSideRailAction("profile-menu")
                    } label: {
                        FocusAwareView { isFocused in
                            HStack(spacing: 14) {
                                ZStack(alignment: .bottomTrailing) {
                                    Group {
                                        if let url = sideRail.profileImageURL {
                                            CachedRemoteImage(url: url, kind: .avatar, maxPixelSize: 128) {
                                                avatarFallback(initials: sideRail.profileInitials)
                                            }
                                        } else {
                                            avatarFallback(initials: sideRail.profileInitials)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))

                                    // Presence dot
                                    Circle()
                                        .fill(CloudXTheme.Colors.accent)
                                        .frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sideRail.accountName)
                                        .font(CloudXTheme.Fonts.nav)
                                        .foregroundStyle(isHeaderLight ? .black : .white)

                                    HStack(spacing: 6) {
                                        let rawTier = sideRail.accountStatus.uppercased()
                                        let displayTier = rawTier == "RTX3080" ? "ULTIMATE" : rawTier
                                        if !displayTier.isEmpty && displayTier != "FREE" && displayTier != "NIL" && displayTier != "ONLINE" {
                                            Text(displayTier)
                                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                                .foregroundStyle(.black)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule().fill(CloudXTheme.Colors.focusTint)
                                                )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .liquidGlassCapsule()
                            .gamePassFocusRing(isFocused: isFocused, cornerRadius: 28)
                        }
                    }
                    .buttonStyle(CloudLibraryTVButtonStyle())
                    .gamePassDisableSystemFocusEffect()
                    .focused($focusedTopBarItem, equals: .profile)
                }

                Spacer()

                // ── Navigation Tabs ──
                HStack(spacing: 8) {
                    ForEach(sideRail.navItems) { item in
                        Button {
                            onSelectNav(item.id)
                        } label: {
                            FocusAwareView { isFocused in
                                HStack(spacing: 10) {
                                    Image(systemName: item.systemImage)
                                        .font(.system(size: 20, weight: selectedNavID == item.id ? .bold : .medium))
                                        .foregroundStyle(selectedNavID == item.id ? (isHeaderLight ? .black : .white) : (isHeaderLight ? .black.opacity(0.6) : CloudXTheme.Colors.textSecondary))

                                    if selectedNavID == item.id || isFocused {
                                        Text(item.title)
                                            .font(CloudXTheme.Fonts.nav)
                                            .foregroundStyle(isHeaderLight ? .black : .white)
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }

                                    if let badge = item.badgeText {
                                        Text(badge)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(CloudXTheme.Colors.focusTint))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(selectedNavID == item.id ? (isHeaderLight ? Color.black.opacity(0.12) : Color.white.opacity(0.12)) : Color.clear)
                                )
                                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 22)
                                .animation(.easeOut(duration: 0.2), value: selectedNavID == item.id)
                                .animation(.easeOut(duration: 0.15), value: isFocused)
                            }
                        }
                        .buttonStyle(CloudLibraryTVButtonStyle())
                        .gamePassDisableSystemFocusEffect()
                        .focused($focusedTopBarItem, equals: .nav(item.id))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .liquidGlassCapsule()

                Spacer()

                // ── Trailing: Settings + Clock ──
                HStack(spacing: 24) {
                    Button {
                        onSelectSideRailAction("settings")
                    } label: {
                        FocusAwareView { isFocused in
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(isHeaderLight ? .black.opacity(0.6) : CloudXTheme.Colors.textSecondary)
                                .frame(width: 44, height: 44)
                                .gamePassFocusRing(isFocused: isFocused, cornerRadius: 22)
                        }
                    }
                    .buttonStyle(CloudLibraryTVButtonStyle())
                    .gamePassDisableSystemFocusEffect()
                    .focused($focusedTopBarItem, equals: .settings)

                    Text(Date(), style: .time)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(isHeaderLight ? .black : CloudXTheme.Colors.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .liquidGlassCapsule()
            }
            .padding(.horizontal, 60)
            .padding(.top, 36)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.15), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .focusSection()
            .defaultFocus($focusedTopBarItem, .nav(selectedNavID))
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: heroBackgroundURL) { _, newURL in
            if newURL == nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isHeaderLight = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .heroBackgroundLuminanceChanged)) { notification in
            guard let url = notification.userInfo?["url"] as? URL,
                  url == heroBackgroundURL else { return }
            if let isLight = notification.userInfo?["isLight"] as? Bool {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isHeaderLight = isLight
                }
            }
        }
    }

    /// Gradient initials fallback used while profile artwork is unavailable.
    @ViewBuilder
    private func avatarFallback(initials: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [CloudXTheme.Colors.focusTint, CloudXTheme.Colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials.isEmpty ? "P" : initials)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
        }
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
    .environment(AppCoordinator().sessionController)
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
    .environment(AppCoordinator().sessionController)
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
    .environment(AppCoordinator().sessionController)
}
#endif



struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.28), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func liquidGlassCapsule() -> some View {
        self.modifier(LiquidGlassCapsuleModifier())
    }
}
