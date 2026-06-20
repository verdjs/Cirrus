//
//  CloudNowApp.swift
//  CloudNow
//
//  Created by Owen Selles on 11/04/2026.
//

import BackgroundTasks
import SwiftUI
import CloudXCore

@main
struct CloudNowApp: App {
    @State private var authManager = AuthManager()
    @State private var gamesViewModel = GamesViewModel()
    @State private var cloudxCoordinator = AppCoordinator()
    @UIApplicationDelegateAdaptor(CloudXAppDelegate.self) private var appDelegate

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            AuthenticatedShellView()
                .environment(authManager)
                .environment(gamesViewModel)
                .environment(cloudxCoordinator.sessionController)
                .environment(cloudxCoordinator.libraryController)
                .environment(cloudxCoordinator.profileController)
                .environment(cloudxCoordinator.consoleController)
                .environment(cloudxCoordinator.streamController)
                .environment(cloudxCoordinator.shellBootstrapController)
                .environment(cloudxCoordinator.achievementsController)
                .environment(cloudxCoordinator.inputController)
                .environment(cloudxCoordinator.previewExportController)
                .environment(cloudxCoordinator.settingsStore)
                .onAppear { registerBGTasks() }
                .task {
                    await authManager.initialize()
                    appDelegate.coordinator = cloudxCoordinator
                    await cloudxCoordinator.onAppear()
                }
        }
    }

    private func registerBGTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.owenselles.CloudNow.tokenRefresh",
            using: nil
        ) { task in
            Task { @MainActor in
                await authManager.refreshIfNeeded()
                authManager.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }
}
