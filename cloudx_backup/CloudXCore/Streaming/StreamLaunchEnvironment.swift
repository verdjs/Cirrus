// StreamLaunchEnvironment.swift
// Defines stream launch environment for the Streaming surface.
//

import Foundation
// Removed local import for single-target compilation
// Removed local import for single-target compilation

struct StreamLaunchEnvironment: Sendable {
    let streamSettings: SettingsStore.StreamSettings
    let diagnosticsSettings: SettingsStore.DiagnosticsSettings
    let controllerSettings: SettingsStore.ControllerSettings
    let availableRegions: [LoginRegion]
}
