// CloudLibraryLibraryScreenFocus.swift
// Defines cloud library library screen focus for the CloudLibrary / Library surface.
//

import SwiftUI
import CloudXModels

extension CloudLibraryLibraryScreen {
    var defaultGridFocusTileID: String? {
        if let preferredTitleID,
           let preferredTileID = scrollTargetID(for: preferredTitleID),
           state.gridItems.contains(where: { $0.id == preferredTileID }) {
            return preferredTileID
        }

        return state.gridItems.first?.id
    }

    func requestHeaderFocusFromSideRail(scrollProxy: ScrollViewProxy) {
        if let remembered = lastFocusedHeaderTarget {
            switch remembered {
            case .tab(let id) where state.tabs.contains(where: { $0.id == id }):
                requestHeaderFocus(.tab(id), scrollProxy: scrollProxy)
                return
            case .headerButton(let id) where id == "sort":
                requestHeaderFocus(.headerButton(id), scrollProxy: scrollProxy)
                return
            case .headerButton(let id) where id == "sort" || id == "clear-filters":
                focusedTarget = .headerButton(id)
            case .headerButton(let id) where id == "clear-filters" && !state.activeFilterLabels.isEmpty:
                requestHeaderFocus(.headerButton(id), scrollProxy: scrollProxy)
                return
            case .filter(let id) where state.filters.contains(where: { $0.id == id }):
                requestHeaderFocus(.filter(id), scrollProxy: scrollProxy)
                return
            default:
                break
            }
        }

        if state.tabs.contains(where: { $0.id == state.selectedTabID }) {
            requestHeaderFocus(.tab(state.selectedTabID), scrollProxy: scrollProxy)
            return
        }
        if let firstTab = state.tabs.first {
            requestHeaderFocus(.tab(firstTab.id), scrollProxy: scrollProxy)
            return
        }
        if !state.sortLabel.isEmpty {
            requestHeaderFocus(.headerButton("sort"), scrollProxy: scrollProxy)
            return
        }
        requestGridFocus(scrollProxy: scrollProxy)
    }

    func requestHeaderFocus(_ target: LibraryFocusTarget, scrollProxy: ScrollViewProxy) {
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            withAnimation(nil) {
                scrollProxy.scrollTo(Self.headerAnchorID, anchor: .top)
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedTarget = target
        }
    }

    func requestGridFocus(scrollProxy: ScrollViewProxy, prefersFirstVisibleItem: Bool = false) {
        guard !state.gridItems.isEmpty else { return }
        let targetTitleID: TitleID?
        if !prefersFirstVisibleItem,
           let remembered = lastFocusedGridTitleID,
           tileLookup[remembered] != nil {
            targetTitleID = remembered
        } else if let preferredTitleID,
                  let preferredTileID = scrollTargetID(for: preferredTitleID),
                  state.gridItems.contains(where: { $0.id == preferredTileID }) {
            targetTitleID = preferredTitleID
        } else {
            targetTitleID = state.gridItems.first?.titleID
        }
        guard let targetTitleID,
              let targetID = scrollTargetID(for: targetTitleID) else { return }
        pendingFocusTask?.cancel()
        pendingFocusTask = Task { @MainActor in
            withAnimation(nil) { scrollProxy.scrollTo(targetID, anchor: .topLeading) }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedTarget = .tile(targetTitleID)
        }
    }

    func scheduleFocusSettled(targetLabel: String, settledTitleID: TitleID?) {
        focusSettler.schedule {
            NavigationPerformanceTracker.recordFocusSettled(surface: "library", target: targetLabel)
            self.onSettledTileID(settledTitleID)
        }
    }

    func isTopGridRow(index: Int) -> Bool {
        index < Self.defaultGridColumnCount
    }

    func isLeadingGridColumn(index: Int) -> Bool {
        index % Self.defaultGridColumnCount == 0
    }

    func scrollTargetID(for titleID: TitleID) -> String? {
        tileLookup[titleID]?.id
    }
}
