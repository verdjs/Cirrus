// CloudXApp.swift
// Defines the app entry point and injects the shared controller graph into SwiftUI.
//

import SwiftUI
import CloudXCore

@main
/// Boots the CloudX app and wires the shared `AppCoordinator` into the root scene.
struct CloudXApp: App {
    @UIApplicationDelegateAdaptor(CloudXAppDelegate.self) private var appDelegate

    @State private var coordinator = AppCoordinator()

    /// Creates the main window group and starts coordinator-driven boot only for normal app runs.
    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
                .environment(coordinator.sessionController)
                .environment(coordinator.libraryController)
                .environment(coordinator.profileController)
                .environment(coordinator.consoleController)
                .environment(coordinator.streamController)
                .environment(coordinator.shellBootstrapController)
                .environment(coordinator.achievementsController)
                .environment(coordinator.inputController)
                .environment(coordinator.previewExportController)
                .environment(coordinator.settingsStore)
                .task {
                    appDelegate.coordinator = coordinator
                    guard shouldRunCoordinatorOnAppear else { return }
                    await coordinator.onAppear()
                }
        }
    }

    /// Skips normal coordinator boot when a UI harness owns startup sequencing.
    private var shouldRunCoordinatorOnAppear: Bool {
        !CloudXLaunchMode.isShellUITestModeEnabled
            && !CloudXLaunchMode.isGamePassHomeUITestModeEnabled
    }
}
