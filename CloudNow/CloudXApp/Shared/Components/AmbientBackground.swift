// AmbientBackground.swift
// Defines ambient background for the Shared / Components surface.
//

import SwiftUI
import CloudXCore

/// Shared gradient stack that preserves foreground readability over hero or artwork-backed backgrounds.
struct BackdropGradientOverlay: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.18), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [CloudXTheme.Colors.bgTop.opacity(0.95), .clear, .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.clear, Color.clear, CloudXTheme.Colors.bgBottom.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// Full-screen shell background that blends gradients with optional remote hero artwork and
/// adapts contrast/blur when high-visibility focus is enabled.
struct CloudLibraryAmbientBackground: View {
    let imageURL: URL?
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let highVisibilityFocus = settingsStore.accessibility.highVisibilityFocus
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [CloudXTheme.Colors.bgTop, CloudXTheme.Colors.bgBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Group {
                    if let imageURL, !ProcessInfo.isLowPerformanceDevice {
                        CachedRemoteImage(
                            url: imageURL,
                            kind: .hero,
                            priority: .low,
                            maxPixelSize: 1_920,
                            analyzeLuminance: true
                        ) {
                            accentBackground
                        }
                        .scaledToFill()
                        .saturation(highVisibilityFocus ? 0.82 : 0.95)
                        .blur(radius: highVisibilityFocus ? 8 : 16)
                        .opacity(highVisibilityFocus ? 0.30 : 0.55)
                    } else {
                        accentBackground
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                BackdropGradientOverlay()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    /// Fallback accent treatment used when no remote artwork is available or while hero imagery loads.
    private var accentBackground: some View {
        ZStack {
            RadialGradient(
                colors: [CloudXTheme.Colors.accent.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 120,
                endRadius: 820
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.14), .clear],
                center: .bottomLeading,
                startRadius: 120,
                endRadius: 900
            )
        }
    }
}

extension View {
    /// Standard outer-frame behavior for full-width shell surfaces that should stay left aligned.
    func gamePassOuterFrame() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("CloudXTheme", traits: .fixedLayout(width: 1920, height: 1080)) {
    ZStack {
        CloudLibraryAmbientBackground(imageURL: nil)
        BackdropGradientOverlay()
    }
    .environment(SettingsStore())
}
#endif
