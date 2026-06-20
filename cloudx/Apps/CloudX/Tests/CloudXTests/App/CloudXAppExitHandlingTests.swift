// CloudXAppExitHandlingTests.swift
// Exercises cloudx app exit handling behavior.
//

import Testing

#if canImport(CloudX)
@testable import CloudX
#endif

struct CloudXAppExitHandlingTests {
    @Test
    func exitHandlingDecision_doesNotConsumeBackAtStableHomeRoot() {
        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: nil,
                selectedTile: nil,
                streamOverlayVisible: false,
                primaryRoute: .home,
                isSideRailExpanded: true
            ).shouldConsumeBackEvent == false
        )
    }

    @Test
    func exitHandlingDecision_consumesBackForUtilityDetailOverlayAndCollapsedRailStates() throws {
        let selectedTile = try #require(CloudLibraryPreviewData.library.gridItems.first)

        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: .settings,
                selectedTile: nil,
                streamOverlayVisible: false,
                primaryRoute: .home,
                isSideRailExpanded: true
            ).shouldConsumeBackEvent
        )

        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: nil,
                selectedTile: selectedTile,
                streamOverlayVisible: false,
                primaryRoute: .home,
                isSideRailExpanded: true
            ).shouldConsumeBackEvent
        )

        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: nil,
                selectedTile: nil,
                streamOverlayVisible: true,
                primaryRoute: .home,
                isSideRailExpanded: true
            ).shouldConsumeBackEvent
        )

        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: nil,
                selectedTile: nil,
                streamOverlayVisible: false,
                primaryRoute: .library,
                isSideRailExpanded: true
            ).shouldConsumeBackEvent
        )

        #expect(
            ShellExitHandlingDecision.resolve(
                utilityRoute: nil,
                selectedTile: nil,
                streamOverlayVisible: false,
                primaryRoute: .home,
                isSideRailExpanded: false
            ).shouldConsumeBackEvent
        )
    }
}
