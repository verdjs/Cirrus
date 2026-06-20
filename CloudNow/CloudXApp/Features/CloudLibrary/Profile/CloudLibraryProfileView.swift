// CloudLibraryProfileView.swift
// Defines the cloud library profile view used in the CloudLibrary / Profile surface.
//

import CloudXCore
import Foundation
import SwiftUI

struct CloudLibraryProfileView: View {
    enum Action: Hashable {
        case openConsoles
        case openSettings
        case refreshProfile
        case refreshFriends
        case signOut
    }

    let profileName: String
    let profileStatus: String
    let profileStatusDetail: String
    let profileDetail: String
    let profileImageURL: URL?
    let profileInitials: String
    let gameDisplayName: String?
    let gamertag: String?
    let gamerscore: String?
    let cloudLibraryCount: Int
    let consoleCount: Int
    let friendsCount: Int
    let friendsLastUpdatedAt: Date?
    let friendsErrorText: String?
    var onOpenConsoles: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRefreshProfileData: () -> Void = {}
    var onRefreshFriends: () -> Void = {}
    var onSignOut: () -> Void = {}
    var onRequestSideRailEntry: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedAction: Action?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            // Left Column: User info & stats
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .center, spacing: 24) {
                    profileAvatar
                        .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayName)
                            .font(CloudXTypography.rounded(34, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        if let secondaryName, !secondaryName.isEmpty {
                            Text(secondaryName)
                                .font(CloudXTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary)
                        }

                        if let gamerscore = sanitized(gamerscore) {
                            Label("\(gamerscore)G", systemImage: "star.fill")
                                .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(CloudXTheme.Colors.focusTint)
                        }
                    }
                }

                Divider()
                    .background(Color.primary.opacity(0.15))

                // Stat list
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Presence / Status
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PRESENCE")
                                .font(CloudXTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary.opacity(0.7))

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(profileStatusBadgeFill)
                                    .frame(width: 12, height: 12)
                                Text(profileStatus)
                                    .font(CloudXTypography.rounded(18, weight: .semibold, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.primary)
                            }

                            if !profileStatusDetail.isEmpty {
                                Text(profileStatusDetail)
                                    .font(CloudXTypography.rounded(16, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary)
                            }
                        }

                        // Library Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CLOUD LIBRARY")
                                .font(CloudXTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary.opacity(0.7))

                            Label("\(cloudLibraryCount) cloud titles ready", systemImage: "cloud.fill")
                                .font(CloudXTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary)
                        }

                        // Consoles Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONSOLES")
                                .font(CloudXTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary.opacity(0.7))

                            Label("\(consoleCount) consoles configured", systemImage: "tv.fill")
                                .font(CloudXTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary)
                        }

                        // Friends Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SOCIAL")
                                .font(CloudXTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary.opacity(0.7))

                            Label(friendsCount == 1 ? "1 friend profile loaded" : "\(friendsCount) friend profiles loaded", systemImage: "person.2.fill")
                                .font(CloudXTypography.rounded(18, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(Color.secondary)

                            if let friendsRefreshText, !friendsRefreshText.isEmpty {
                                Text(friendsRefreshText)
                                    .font(CloudXTypography.rounded(14, weight: .regular, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                            }

                            if let friendsErrorText, !friendsErrorText.isEmpty {
                                Label(friendsErrorText, systemImage: "exclamationmark.triangle.fill")
                                    .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.red)
                            }
                        }

                        // Diagnostics/Session Info
                        if !profileDetail.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SESSION INFO")
                                    .font(CloudXTypography.rounded(14, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary.opacity(0.7))

                                Text(profileDetail)
                                    .font(CloudXTypography.rounded(15, weight: .regular, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(width: 500, alignment: .leading)

            // Right Column: Vertical list of actions
            VStack(alignment: .leading, spacing: 24) {
                Text("ACTIONS")
                    .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(CloudXTheme.Colors.focusTint)
                    .padding(.leading, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        actionButton(
                            title: "Consoles",
                            subtitle: "View and connect to your Xbox consoles",
                            systemImage: "tv.fill",
                            focusTarget: .openConsoles,
                            accessibilityIdentifier: "profile_rail_consoles",
                            wantsRailEntryOnLeft: true,
                            action: onOpenConsoles
                        )

                        actionButton(
                            title: "Settings",
                            subtitle: "Configure streaming, network, and layout settings",
                            systemImage: "gearshape.fill",
                            focusTarget: .openSettings,
                            accessibilityIdentifier: "profile_rail_settings",
                            action: onOpenSettings
                        )

                        actionButton(
                            title: "Refresh Profile",
                            subtitle: "Reload Xbox profile metadata and achievements",
                            systemImage: "arrow.clockwise",
                            focusTarget: .refreshProfile,
                            wantsRailEntryOnLeft: true,
                            action: onRefreshProfileData
                        )

                        actionButton(
                            title: "Refresh Friends List",
                            subtitle: "Sync social presence status",
                            systemImage: "person.2.badge.gearshape.fill",
                            focusTarget: .refreshFriends,
                            action: onRefreshFriends
                        )

                        actionButton(
                            title: "Sign Out",
                            subtitle: "Sign out of your Xbox Live session",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            focusTarget: .signOut,
                            accessibilityIdentifier: "profile_rail_signout",
                            wantsRailEntryOnLeft: true,
                            destructive: true,
                            action: onSignOut
                        )
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, CloudXTheme.Shell.contentTopPadding)
        .padding(.horizontal, CloudXTheme.Layout.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .colorScheme(.dark)
        .accessibilityIdentifier("route_profile_root")
    }

    private var displayName: String {
        sanitized(gameDisplayName) ?? profileName
    }

    private var secondaryName: String? {
        if let gamertag = sanitized(gamertag), gamertag != displayName {
            return gamertag
        }
        if displayName != profileName {
            return profileName
        }
        return nil
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let profileImageURL {
            CachedRemoteImage(
                url: profileImageURL,
                kind: .avatar,
                priority: .normal,
                maxPixelSize: 256,
                contentMode: .fill
            ) {
                avatarFallback
            }
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [CloudXTheme.Colors.focusTint, CloudXTheme.Colors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(profileInitials.isEmpty ? "P" : profileInitials)
                .font(CloudXTypography.rounded(30, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(Color.black.opacity(0.82))
        }
        .overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 1))
    }

    private var friendsRefreshText: String? {
        guard let friendsLastUpdatedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Friends refreshed \(formatter.localizedString(for: friendsLastUpdatedAt, relativeTo: Date()))"
    }

    private var profileStatusBadgeFill: Color {
        let lower = profileStatus.lowercased()
        if lower.contains("offline") {
            return Color.white.opacity(0.10)
        }
        if lower.contains("busy") || lower.contains("away") {
            return Color.orange.opacity(0.22)
        }
        return CloudXTheme.Colors.focusTint
    }

    private var profileStatusBadgeTextColor: Color {
        let lower = profileStatus.lowercased()
        if lower.contains("offline") || lower.contains("busy") || lower.contains("away") {
            return CloudXTheme.Colors.textPrimary
        }
        return .black
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        focusTarget: Action,
        accessibilityIdentifier: String? = nil,
        wantsRailEntryOnLeft: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32)
                    .foregroundStyle(destructive ? Color.white : Color.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(destructive ? Color.white : Color.primary)
                    Text(subtitle)
                        .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(destructive ? Color.white.opacity(0.7) : Color.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(destructive ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? Color.red.opacity(0.8) : nil)
        .focused($focusedAction, equals: focusTarget)
        .modifier(DefaultProfileFocusModifier(focusedAction: $focusedAction, focusTarget: focusTarget))
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .onMoveCommand { direction in
            guard wantsRailEntryOnLeft, direction == .left else { return }
            onRequestSideRailEntry()
        }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DefaultProfileFocusModifier: ViewModifier {
    let focusedAction: FocusState<CloudLibraryProfileView.Action?>.Binding
    let focusTarget: CloudLibraryProfileView.Action

    @ViewBuilder
    func body(content: Content) -> some View {
        if focusTarget == .openConsoles {
            content.defaultFocus(focusedAction, .openConsoles)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("CloudLibraryProfileView", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibraryProfileView(
        profileName: "cloudx-preview",
        profileStatus: "Online",
        profileStatusDetail: "Playing Forza Horizon 5",
        profileDetail: "Balanced latency • H.264 • Low latency • Stats on",
        profileImageURL: nil,
        profileInitials: "S",
        gameDisplayName: "CloudX Preview",
        gamertag: "cloudx-preview",
        gamerscore: "88,420",
        cloudLibraryCount: 248,
        consoleCount: 2,
        friendsCount: 44,
        friendsLastUpdatedAt: Date().addingTimeInterval(-180),
        friendsErrorText: nil
    )
}
#endif
