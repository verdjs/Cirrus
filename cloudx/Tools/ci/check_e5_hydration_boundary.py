#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_not_contains, fail

errors: list[str] = []

required_paths = [
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationOrchestrator.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationRequest.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationCommitContext.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationLiveFetchResult.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationCommitResult.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationOrchestrationResult.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationPersistenceIntent.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationStartupRestoreWorkflow.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydrationPostStreamDeltaWorkflow.swift"),
]
errors.extend(require_paths(required_paths))

legacy_monolith = rel("Packages/CloudXCore/Sources/CloudXCore/Hydration/LibraryHydration.swift")
if legacy_monolith.exists():
    errors.append(f"{legacy_monolith}: legacy hydration monolith must not exist.")

library_controller = rel("Packages/CloudXCore/Sources/CloudXCore/LibraryController.swift")
errors.extend(
    assert_not_contains(
        library_controller,
        [
            "func applyStartupRestoreResult(",
            "func applyHydrationRecoveryState(",
            "func applyHydrationPublishedState(",
            "func applyProductDetailsState(",
        ],
    )
)

fail(errors)
print("Stage 2 hydration boundary guard passed.")
