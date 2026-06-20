// CloudLibrarySettingsView.swift
// Defines the unified cloud library settings view.
//

import SwiftUI
import CloudXCore
import CloudXModels

struct CloudLibrarySettingsView: View {
    @Binding var selectedPane: CloudLibrarySettingsPane

    let profileName: String
    let profileInitials: String
    let profileImageURL: URL?
    let profileStatusText: String
    let profileStatusDetail: String
    let cloudLibraryCount: Int
    let consoleCount: Int
    let isLoadingCloudLibrary: Bool
    let regionOverrideDiagnostics: String?
    var onRefreshCloudLibrary: () -> Void = {}
    var onRefreshConsoles: () -> Void = {}
    var onSignOut: () -> Void = {}
    var onRequestSideRailEntry: () -> Void = {}
    var onExportPreviewDump: () async -> String = { "" }

    @Environment(SettingsStore.self) var settingsStore
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(AuthManager.self) var authManager
    @Environment(GamesViewModel.self) var gamesViewModel
    @Environment(SessionController.self) var sessionController
    @SceneStorage("cloudx.gamepass.settings.advanced_mode") var isAdvancedMode = false
    @FocusState var focusedPane: CloudLibrarySettingsPane?
    @State var exportTask: Task<Void, Never>?
    @State var exportFeedback: String?
    @State var isExportingPreviewDump = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                Text("Settings")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
                    .padding(.bottom, 10)

                // 1. Xbox Cloud Gaming Settings
                xboxSection

                // 2. GeForce NOW Settings
                gfnSection

                // 3. General Settings
                generalSettingsSection

                // 4. Credits & Thanks
                creditsSection

                // 5. Advanced Settings Toggle & Section
                VStack(alignment: .leading, spacing: 20) {
                    CloudLibraryToggleRow(
                        title: "Advanced Settings Mode",
                        subtitle: "Show deeper connection, codec, and diagnostic settings",
                        isOn: $isAdvancedMode
                    )
                    
                    if isAdvancedMode {
                        advancedSettingsSection
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, CloudXTheme.Layout.outerPadding)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .colorScheme(.dark)
        .accessibilityIdentifier("route_settings_root")
        .onDisappear {
            exportTask?.cancel()
        }
    }

    // MARK: - Sections

    private var xboxSection: some View {
        CloudLibraryPageSectionCard(title: "Xbox Cloud Gaming") {
            VStack(alignment: .leading, spacing: 12) {
                if isXboxSignedIn {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in as \(profileName)")
                                .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            if !profileStatusDetail.isEmpty || !profileStatusText.isEmpty {
                                Text(profileStatusDetail.isEmpty ? profileStatusText : profileStatusDetail)
                                    .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        
                        Button(role: .destructive) {
                            onSignOut()
                        } label: {
                            Text("Sign Out")
                                .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    
                    CloudLibrarySettingsActionButton(title: "Refresh Game Pass Catalog", systemImage: "arrow.clockwise", action: onRefreshCloudLibrary)
                    CloudLibrarySettingsActionButton(title: "Refresh Consoles", systemImage: "tv.badge.wifi", action: onRefreshConsoles)
                } else {
                    Button {
                        Task { await sessionController.beginSignIn() }
                    } label: {
                        HStack {
                            Image(systemName: "xbox.logo")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sign In to Xbox Cloud Gaming")
                                    .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                Text("Connect your Microsoft account to stream xCloud titles")
                                    .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                    .background(Color.primary.opacity(0.12))
                    .padding(.vertical, 4)
                
                // Xbox Quality Settings
                CloudLibraryPickerRow(title: "Stream Quality Preset", selection: streamBinding(\.qualityPreset), options: ["Low Data", "Balanced", "High Quality"])
                CloudLibraryPickerRow(title: "Stream Resolution", selection: streamBinding(\.preferredResolution), options: ["720p", "1080p", "1440p"])
                CloudLibraryPickerRow(title: "Stream Frame Rate", selection: streamBinding(\.preferredFPS), options: ["30", "60"])
                CloudLibraryToggleRow(title: "Show Stream Diagnostics HUD", subtitle: "Display live stream telemetry during play", isOn: streamBinding(\.showStreamStats))
            }
        }
    }

    private var gfnSection: some View {
        CloudLibraryPageSectionCard(title: "GeForce NOW") {
            VStack(alignment: .leading, spacing: 12) {
                if authManager.isAuthenticated {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let sub = gamesViewModel.subscription {
                                Text("Signed in • \(sub.membershipTier)")
                                    .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                if let remaining = sub.remainingMinutes {
                                    Text("Remaining Time: \(remaining) minutes")
                                        .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                        .foregroundStyle(Color.secondary)
                                } else if sub.isUnlimited {
                                    Text("Remaining Time: Unlimited")
                                        .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                        .foregroundStyle(Color.secondary)
                                }
                            } else {
                                Text("Signed in to GeForce NOW")
                                    .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                            }
                        }
                        Spacer()
                        
                        Button(role: .destructive) {
                            authManager.logout()
                            gamesViewModel.libraryGames = []
                        } label: {
                            Text("Sign Out")
                                .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                } else {
                    Button {
                        authManager.login()
                    } label: {
                        HStack {
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sign In to GeForce NOW")
                                    .font(CloudXTypography.rounded(18, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                                Text("Stream owned Steam, Epic, and Ubisoft games on G-NOW")
                                    .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                    .background(Color.primary.opacity(0.12))
                    .padding(.vertical, 4)
                
                // G-NOW Quality Settings
                CloudLibraryPickerRow(title: "G-NOW Target Resolution", selection: GFNResolutionBinding, options: ["1080p (FHD)", "1440p (QHD)", "2160p (4K UHD)"])
                CloudLibraryPickerRow(title: "G-NOW Target Framerate", selection: GFNFPSBinding, options: ["60 FPS", "120 FPS"])
                CloudLibraryPickerRow(title: "G-NOW Maximum Bitrate", selection: GFNBitrateBinding, options: ["Auto (Recommended)", "35 Mbps", "50 Mbps", "75 Mbps"])
            }
        }
    }

    private var generalSettingsSection: some View {
        CloudLibraryPageSectionCard(title: "General Settings") {
            VStack(alignment: .leading, spacing: 12) {
                // Accessibility / Comfort
                CloudLibraryToggleRow(title: "Large Text Size", subtitle: "Increase shell text sizing for comfort", isOn: accessibilityBinding(\.largeText))
                CloudLibraryToggleRow(title: "Reduce Motion", subtitle: "Minimize transition animations", isOn: accessibilityBinding(\.reduceMotion))
                CloudLibraryToggleRow(title: "High Visibility Focus", subtitle: "Thicker focus highlights", isOn: accessibilityBinding(\.highVisibilityFocus))
                CloudLibraryPickerRow(
                    title: "Upscaling Quality Mode",
                    selection: upscalingModeBinding,
                    options: upscalingOptions
                )
                Text("Disclaimer: Upscaling mode might not work or could cause frame drops on older hardware.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 16)
                    .padding(.top, -8)
                
                // Controller Settings
                CloudLibraryToggleRow(title: "Controller Vibration / Rumble", subtitle: "Enable standard gamepad haptic feedback", isOn: controllerBinding(\.vibrationEnabled))
                CloudLibraryToggleRow(title: "Swap A / B Buttons", subtitle: "Alternative layout for select/back actions", isOn: controllerBinding(\.swapABButtons))
                CloudLibraryToggleRow(title: "Invert Y Axis", subtitle: "Inverts camera look pitch orientation", isOn: controllerBinding(\.invertYAxis))
                CloudLibrarySliderRow(title: "Stick Deadzone", value: controllerBinding(\.deadzone), range: 0...0.35, formatter: decimalText)
                CloudLibrarySliderRow(title: "Trigger Sensitivity", value: controllerBinding(\.triggerSensitivity), range: 0...1.0, formatter: decimalText)
                CloudLibraryPickerRow(title: "Trigger Interpretation Mode", selection: triggerModeBinding, options: ["Auto", "Compatibility", "Analog"])
                CloudLibrarySliderRow(title: "Sensitivity Boost", value: controllerBinding(\.sensitivityBoost), range: 0...1.0, formatter: decimalText)
                CloudLibrarySliderRow(title: "Vibration Intensity Scale", value: controllerBinding(\.vibrationIntensity), range: 0...1.0, formatter: decimalText)
                
                // Video & Audio Settings
                CloudLibraryPickerRow(title: "Output Color Range", selection: streamBinding(\.colorRange), options: ["Auto", "Limited", "Full"])
                CloudLibrarySliderRow(title: "Safe Area Zoom Inset", value: streamBinding(\.safeAreaPercent), range: 80...100, formatter: wholePercentText)
                CloudLibrarySliderRow(title: "Audio Level Boost", value: streamBinding(\.audioBoost), range: 0...12.0, formatter: audioBoostText, step: 1)
                CloudLibraryToggleRow(title: "Prefer Stereo Output", subtitle: "Downmix surround channels locally", isOn: streamBinding(\.stereoAudio))
                CloudLibraryToggleRow(title: "Default Chat Channel", subtitle: "Maintain voice session across titles", isOn: streamBinding(\.chatChannelEnabled))
            }
        }
    }

    private var creditsSection: some View {
        CloudLibraryPageSectionCard(title: "Credits & Thanks") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cirrus is a combined game streaming client for Apple TV, bringing together NVIDIA GeForce NOW and Xbox Cloud Gaming into a single unified native experience.")
                    .font(CloudXTypography.rounded(15, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                
                VStack(alignment: .leading, spacing: 12) {
                    creditRow(title: "Owen Selles", role: "Creator of CloudNow (GeForce NOW client)")
                    creditRow(title: "nafields", role: "Creator of Stratix (Xbox Game Pass / xCloud client)")
                    creditRow(title: "unknownskl", role: "Streaming protocol research, greenlight, & xbox-xcloud-player")
                    creditRow(title: "PrintedWaste", role: "Community GFN regional zone API")
                    creditRow(title: "LiveKit & WebRTC", role: "Real-time transport rendering and SDK libraries")
                }
                .padding(.top, 4)
            }
        }
    }
    
    private func creditRow(title: String, role: String) -> some View {
        HStack {
            Text(title)
                .font(CloudXTypography.rounded(16, weight: .bold, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(.white)
            Spacer()
            Text(role)
                .font(CloudXTypography.rounded(14, weight: .medium, dynamicTypeSize: dynamicTypeSize))
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.02)))
    }

    private var advancedSettingsSection: some View {
        CloudLibraryPageSectionCard(title: "Advanced Settings") {
            LazyVStack(alignment: .leading, spacing: 12) {
                // Diagnostic Settings
                CloudLibraryPickerRow(title: "Region Override", selection: streamBinding(\.regionOverride), options: ["Auto", "US East", "US West", "Europe", "UK"])
                if let regionOverrideDiagnostics, !regionOverrideDiagnostics.isEmpty {
                    CloudLibraryStatLine(icon: "globe", text: regionOverrideDiagnostics)
                }
                CloudLibraryPickerRow(title: "Stream Codec Preference", selection: streamBinding(\.codecPreference), options: ["Auto", "H.264", "VP9"])
                CloudLibraryPickerRow(title: "Stream Client Profile OS", selection: streamBinding(\.clientProfileOSName), options: ["Auto", "Android", "Windows", "Tizen"])
                CloudLibraryPickerRow(title: "Telemetry Overlay HUD Position", selection: streamBinding(\.statsHUDPosition), options: ["topRight", "topLeft", "bottomRight", "bottomLeft"])
                CloudLibrarySliderRow(title: "Manual Bitrate Cap Limit", value: streamBinding(\.bitrateCapMbps), range: 0...100, formatter: bitrateText, step: 4)
                
                CloudLibraryToggleRow(title: "HDR Preferred Peak Metadata", subtitle: "Stream high dynamic range if validated", isOn: streamBinding(\.hdrEnabled))
                CloudLibraryToggleRow(title: "Ultra Low Latency Priority", subtitle: "Bypasses safety frames to decrease RTT latency", isOn: streamBinding(\.lowLatencyMode))
                CloudLibraryToggleRow(title: "Automatic Session Recovery Connection", subtitle: "Retry signaling after carrier drops", isOn: streamBinding(\.autoReconnect))
                CloudLibraryToggleRow(title: "Packet Loss Protection Shield", subtitle: "Adds redundant parity packets on shaky links", isOn: streamBinding(\.packetLossProtection))
                CloudLibraryToggleRow(title: "Prefer IPv6 Carrier Stack", subtitle: "Negotiates ICE transport using IPv6 endpoints", isOn: streamBinding(\.preferIPv6))
                
                CloudLibraryToggleRow(title: "Enable Log Network Event Breadcrumbs", subtitle: "Includes detailed signaling diagnostics in local files", isOn: diagnosticsBinding(\.logNetworkEvents))
                CloudLibraryToggleRow(title: "Block Local Analytics Telemetry", subtitle: "Do not track sessions or features", isOn: diagnosticsBinding(\.blockTracking))
                CloudLibraryToggleRow(title: "Verbose Deeper Runtime Logging", subtitle: "Outputs lower-level connection traces", isOn: diagnosticsBinding(\.verboseLogs))
                
                CloudLibraryToggleRow(title: "Collect Timing Frame Probe Timing", subtitle: "Adds layout pass trace diagnostics", isOn: diagnosticsBinding(\.frameProbe))
                CloudLibraryToggleRow(title: "Audio Drift Resync Watchdog", subtitle: "Monitors and snaps clock offset", isOn: diagnosticsBinding(\.audioResyncWatchdogEnabled))
                CloudLibraryToggleRow(title: "Startup Haptics Rumble Test Probe", subtitle: "Shakes triggers during initialization test", isOn: diagnosticsBinding(\.startupHapticsProbeEnabled))
                
                // Export preview dump action
                CloudLibrarySettingsActionButton(
                    title: previewExportTitle,
                    systemImage: "square.and.arrow.up"
                ) {
                    startPreviewExport()
                }

                if let exportFeedback, !exportFeedback.isEmpty {
                    CloudLibraryStatLine(icon: "doc.fill", text: exportFeedback)
                }
            }
        }
    }

    // MARK: - Helpers & Bindings

    private var isXboxSignedIn: Bool {
        if case .authenticated(_) = sessionController.authState { return true }
        return false
    }

    private var upscalingOptions: [String] {
        if SettingsStore.isLegacyAppleTV() {
            return ["Off", "MetalFX Spatial"]
        } else {
            return ["Off", "MetalFX Spatial", "AMD FSR / CAS (Sharp)", "Apple Super Resolution"]
        }
    }

    private var previewExportTitle: String {
        isExportingPreviewDump ? "Exporting Preview Dump" : "Export Preview Dump"
    }

    private func startPreviewExport() {
        exportTask?.cancel()
        isExportingPreviewDump = true
        exportTask = Task { @MainActor in
            let result = await onExportPreviewDump()
            guard !Task.isCancelled else { return }
            exportFeedback = result
            isExportingPreviewDump = false
        }
    }

    private func bitrateText(_ value: Double) -> String {
        value <= 0 ? "Auto" : String(format: "%.0f Mbps", value)
    }

    private func decimalText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func wholePercentText(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private func audioBoostText(_ value: Double) -> String {
        String(format: "+%.0f dB", value)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private var GFNResolutionBinding: Binding<String> {
        Binding(
            get: {
                switch gamesViewModel.streamSettings.resolution {
                case "1920x1080": return "1080p (FHD)"
                case "2560x1440": return "1440p (QHD)"
                case "3840x2160": return "2160p (4K UHD)"
                default:
                    if gamesViewModel.streamSettings.resolution.contains("3840") || gamesViewModel.streamSettings.resolution.contains("2160") {
                        return "2160p (4K UHD)"
                    } else if gamesViewModel.streamSettings.resolution.contains("2560") || gamesViewModel.streamSettings.resolution.contains("1440") {
                        return "1440p (QHD)"
                    } else {
                        return "1080p (FHD)"
                    }
                }
            },
            set: { newValue in
                var settings = gamesViewModel.streamSettings
                switch newValue {
                case "1080p (FHD)": settings.resolution = "1920x1080"
                case "1440p (QHD)": settings.resolution = "2560x1440"
                case "2160p (4K UHD)": settings.resolution = "3840x2160"
                default: break
                }
                gamesViewModel.streamSettings = settings
                gamesViewModel.saveSettings()
                // Write to legacy key for compatibility/other readers
                UserDefaults.standard.set(newValue, forKey: "gfn_stream_resolution")
            }
        )
    }
    
    private var GFNFPSBinding: Binding<String> {
        Binding(
            get: {
                "\(gamesViewModel.streamSettings.fps) FPS"
            },
            set: { newValue in
                var settings = gamesViewModel.streamSettings
                let fpsString = newValue.replacingOccurrences(of: " FPS", with: "")
                if let fps = Int(fpsString) {
                    settings.fps = fps
                    gamesViewModel.streamSettings = settings
                    gamesViewModel.saveSettings()
                }
                UserDefaults.standard.set(Int(fpsString) ?? 60, forKey: "gfn_stream_fps")
            }
        )
    }
    
    private var GFNBitrateBinding: Binding<String> {
        Binding(
            get: {
                let kbps = gamesViewModel.streamSettings.maxBitrateKbps
                if kbps <= 0 || kbps == 45_000 {
                    return "Auto (Recommended)"
                } else if kbps == 35_000 {
                    return "35 Mbps"
                } else if kbps == 50_000 {
                    return "50 Mbps"
                } else if kbps == 75_000 {
                    return "75 Mbps"
                } else {
                    return "\(kbps / 1000) Mbps"
                }
            },
            set: { newValue in
                var settings = gamesViewModel.streamSettings
                switch newValue {
                case "Auto (Recommended)":
                    settings.maxBitrateKbps = 45_000
                case "35 Mbps":
                    settings.maxBitrateKbps = 35_000
                case "50 Mbps":
                    settings.maxBitrateKbps = 50_000
                case "75 Mbps":
                    settings.maxBitrateKbps = 75_000
                default:
                    let mbpsString = newValue.replacingOccurrences(of: " Mbps", with: "")
                    if let mbps = Int(mbpsString) {
                        settings.maxBitrateKbps = mbps * 1000
                    }
                }
                gamesViewModel.streamSettings = settings
                gamesViewModel.saveSettings()
                UserDefaults.standard.set(newValue, forKey: "gfn_stream_bitrate")
            }
        )
    }
}
