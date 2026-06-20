// StreamStopWorkflow.swift
// Defines stream stop workflow for the Streaming surface.
//

import Foundation
// Removed local import for single-target compilation

struct StreamStopWorkflowEnvironment {
    let runtimeAttachmentEnvironment: StreamRuntimeAttachmentEnvironment
    let priorityModeEnvironment: StreamPriorityModeEnvironment
    let publish: @Sendable @MainActor ([StreamAction]) -> Void
}

@MainActor
final class StreamStopWorkflow {
    private let overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator
    private let runtimeAttachmentService: StreamRuntimeAttachmentService
    private let priorityModeCoordinator: StreamPriorityModeCoordinator

    init(
        overlayVisibilityCoordinator: StreamOverlayVisibilityCoordinator? = nil,
        runtimeAttachmentService: StreamRuntimeAttachmentService? = nil,
        priorityModeCoordinator: StreamPriorityModeCoordinator? = nil
    ) {
        self.overlayVisibilityCoordinator = overlayVisibilityCoordinator ?? StreamOverlayVisibilityCoordinator()
        self.runtimeAttachmentService = runtimeAttachmentService ?? StreamRuntimeAttachmentService()
        self.priorityModeCoordinator = priorityModeCoordinator ?? StreamPriorityModeCoordinator()
    }

    func stop(
        state: StreamState,
        reconnectCoordinator: StreamReconnectCoordinator,
        environment: StreamStopWorkflowEnvironment
    ) async {
        await overlayVisibilityCoordinator.stopPresentationRefresh()
        await reconnectCoordinator.reset()

        environment.publish([
            .reconnectStateReset,
            .overlayVisibilityChanged(false, trigger: .explicitExit),
            .achievementSnapshotSet(nil),
            .achievementErrorSet(nil),
            .launchHeroURLSet(nil),
            .activeLaunchTargetSet(nil)
        ])

        environment.publish(
            runtimeAttachmentService.detach(
                environment: environment.runtimeAttachmentEnvironment
            )
        )
        await runtimeAttachmentService.disconnect(session: state.streamingSession)
        await priorityModeCoordinator.exit(
            state: state,
            environment: environment.priorityModeEnvironment,
            publish: environment.publish
        )
    }
}
