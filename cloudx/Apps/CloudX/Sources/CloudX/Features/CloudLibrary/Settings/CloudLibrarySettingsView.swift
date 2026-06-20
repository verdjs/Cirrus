// CloudLibrarySettingsView.swift
// Defines the cloud library settings view used in the CloudLibrary / Settings surface.
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
                    .foregroundStyle(CloudXTheme.Colors.textPrimary)
                    .padding(.bottom, 10)

                // 1. Xbox Cloud Gaming Settings
                xboxSection

                // 2. General Settings
                generalSettingsSection

                // 3. Advanced Settings Toggle & Section
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                    
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
                    .background(Color.white.opacity(0.12))
                    .padding(.vertical, 4)
                
                // Xbox Quality Settings
                CloudLibraryPickerRow(title: "Stream Quality Preset", selection: streamBinding(\.qualityPreset), options: ["Low Data", "Balanced", "High Quality"])
                CloudLibraryPickerRow(title: "Stream Resolution", selection: streamBinding(\.preferredResolution), options: ["720p", "1080p", "1440p"])
                CloudLibraryPickerRow(title: "Stream Frame Rate", selection: streamBinding(\.preferredFPS), options: ["30", "60"])
                CloudLibraryToggleRow(title: "Show Stream Diagnostics HUD", subtitle: "Display live stream telemetry during play", isOn: streamBinding(\.showStreamStats))
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

    private var advancedSettingsSection: some View {
        CloudLibraryPageSectionCard(title: "Advanced Settings") {
            VStack(alignment: .leading, spacing: 12) {
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
}

#if DEBUG
private struct CloudLibrarySettingsPreviewHost: View {
    @State private var pane: CloudLibrarySettingsPane = .overview
    @State private var coordinator = AppCoordinator()

    var body: some View {
        CloudLibrarySettingsView(
            selectedPane: $pane,
            profileName: "cloudx-preview",
            profileInitials: "S",
            profileImageURL: nil,
            profileStatusText: "Online",
            profileStatusDetail: "Playing Forza Horizon 5",
            cloudLibraryCount: 248,
            consoleCount: 2,
            isLoadingCloudLibrary: false,
            regionOverrideDiagnostics: nil
        )
        .environment(coordinator.settingsStore)
        .environment(coordinator.sessionController)
    }
}

#Preview("CloudLibrarySettingsView", traits: .fixedLayout(width: 1920, height: 1080)) {
    CloudLibrarySettingsPreviewHost()
}
#endif
