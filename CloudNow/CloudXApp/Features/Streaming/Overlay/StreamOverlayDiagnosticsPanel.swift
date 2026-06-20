// StreamOverlayDiagnosticsPanel.swift
// Defines stream overlay diagnostics panel for the Streaming / Overlay surface.
//

import SwiftUI
import CloudXModels
import StreamingCore
import Charts

/// Shows the in-stream diagnostics panel with game info, achievements, stats, and actions.
struct StreamOverlayDetailsPanel: View {
    let session: any StreamingSessionFacade
    let surfaceModel: StreamSurfaceModel
    let overlayState: StreamOverlayState
    let pingHistory: [Double]
    let fpsHistory: [Double]
    let bitrateHistory: [Double]
    let onCloseOverlay: () -> Void
    let onDisconnect: () -> Void
    @FocusState var focusedTarget: StreamOverlayState.FocusTarget?
    @FocusState private var isResumeFocused: Bool

    /// Renders the detail panel and keeps the requested focus target synchronized.
    var body: some View {
        ZStack {
            Color.clear
                .liquidGlass()
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 40) {
                // Actions (Left Column)
                VStack(spacing: 16) {
                    Button(action: onCloseOverlay) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .focused($isResumeFocused)

                    Button(role: .destructive, action: onDisconnect) {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .focused($focusedTarget, equals: StreamOverlayState.FocusTarget.disconnect)
                    .accessibilityIdentifier("stream_disconnect_button")
                }

                // Live stats (Right Column)
                VStack(alignment: .leading, spacing: 10) {
                    metricRow(
                        icon: "network",
                        label: "RTT",
                        value: session.stats.roundTripTimeMs.map { String(format: "%.0f ms", $0) } ?? "—",
                        history: pingHistory,
                        color: pingColor(session.stats.roundTripTimeMs ?? 0)
                    )
                    metricRow(
                        icon: "speedometer",
                        label: "FPS",
                        value: session.stats.framesPerSecond.map { String(format: "%.0f fps", $0) } ?? "—",
                        history: fpsHistory,
                        color: fpsColor(session.stats.framesPerSecond ?? 0)
                    )
                    metricRow(
                        icon: "wifi",
                        label: "Bitrate",
                        value: session.stats.bitrateKbps.map { "\($0 / 1000) Mbps" } ?? "—",
                        history: bitrateHistory,
                        color: .cyan
                    )
                    Divider().overlay(.white.opacity(0.4))
                    Label("\(overlayOutputResolutionText) @ \(session.stats.framesPerSecond.map { String(format: "%.0f fps", $0) } ?? "—")", systemImage: "tv")
                    Label("Loss \(session.stats.packetsLost.map(String.init) ?? "—")", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
            }
            .padding(32)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(60)
        }
        .background {
            Button(action: onCloseOverlay) {
                Color.clear
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityHidden(true)
            .accessibilityLabel("Close overlay")
        }
        .onAppear {
            syncFocus(using: overlayState.focusTarget)
        }
        .onChange(of: overlayState.focusTarget, initial: true) { _, nextFocusTarget in
            syncFocus(using: nextFocusTarget)
        }
    }

    private func metricRow(icon: String, label: String, value: String, history: [Double], color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            Text("\(label): \(value)")
                .foregroundStyle(color)
                .frame(width: 130, alignment: .leading)
            if history.count > 1 {
                Chart {
                    ForEach(Array(history.enumerated()), id: \.offset) { (idx, val) in
                        LineMark(x: .value("t", idx), y: .value("v", val))
                            .foregroundStyle(color)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 80, height: 24)
            }
        }
    }

    private func pingColor(_ ms: Double) -> Color {
        if ms < 30  { return .green }
        if ms < 80  { return .yellow }
        if ms < 150 { return .orange }
        return .red
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }

    /// Shared card shell used by the detail panel sections.
    func infoCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(
            cornerRadius: 18,
            fill: Color.white.opacity(0.04),
            stroke: Color.white.opacity(0.08),
            shadowOpacity: 0.06
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CloudXTheme.Colors.focusTint)
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CloudXTheme.Colors.textMuted)
                        .textCase(.uppercase)
                }

                content()
            }
            .padding(16)
        }
    }

    private func syncFocus(using target: StreamOverlayState.FocusTarget?) {
        guard let target else {
            focusedTarget = nil
            isResumeFocused = true
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard overlayState.showsDetailsPanel else { return }
            focusedTarget = target
            isResumeFocused = false
        }
    }
}
