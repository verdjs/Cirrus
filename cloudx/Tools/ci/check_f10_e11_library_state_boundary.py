#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Packages/CloudXCore/Sources/CloudXCore/LibraryState.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/LibraryAction.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/LibraryReducer.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/LibraryRuntimeState.swift"),
    rel("Packages/CloudXModels/Sources/CloudXModels/Identifiers/TitleID.swift"),
    rel("Packages/CloudXModels/Sources/CloudXModels/Identifiers/ProductID.swift"),
]
errors.extend(require_paths(required_paths))

library_controller = rel("Packages/CloudXCore/Sources/CloudXCore/LibraryController.swift")

errors.extend(
    assert_contains(
        library_controller,
        [
            "var state: LibraryState",
            "func apply(_ action: LibraryAction)",
        ],
    )
)

errors.extend(
    assert_not_contains(
        library_controller,
        [
            "func setSections(",
            "func setProductDetails(",
            "func setIsLoading(",
            "func setLastError(",
            "func setNeedsReauth(",
            "func setLastHydratedAt(",
            "func setHomeMerchandising(",
            "func setHasCompletedInitialHomeMerchandising(",
            "func setHomeMerchandisingSessionSource(",
            "func setHasRecoveredLiveHomeMerchandisingThisSession(",
            "func setHomeDiscoveryEntries(",
            "func setCacheSavedAt(",
            "func setIsArtworkPrefetchThrottled(",
        ],
    )
)

library_reducer = rel("Packages/CloudXCore/Sources/CloudXCore/LibraryReducer.swift")
errors.extend(
    assert_contains(
        library_reducer,
        [
            "static func reduce(",
            "state: LibraryState",
            "action: LibraryAction",
        ],
    )
)

fail(errors)
print("Stage 3 library state boundary guard passed.")
