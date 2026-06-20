// CloudLibraryDetailRouteActions.swift
// Defines cloud library detail route actions for the Features / CloudLibrary surface.
//

import CloudXModels

struct CloudLibraryDetailRouteActions {
    let launchStream: @MainActor (TitleID, String) -> Void
    let secondaryAction: @MainActor (CloudLibraryActionViewState) -> Void
}
