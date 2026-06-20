#!/usr/bin/env python3
from __future__ import annotations

from common import rel, fail

errors: list[str] = []

targets = [
    rel("Apps/CloudX/Sources/CloudX/Features/CloudLibrary"),
    rel("Apps/CloudX/CloudXTests"),
    rel("Apps/CloudX/CloudXUITests"),
]

forbidden = [
    "CloudLibraryNavigationModel",
    "CloudLibraryPresentationModel",
]

for target in targets:
    if not target.exists():
        continue

    for path in target.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for needle in forbidden:
            if needle in text:
                errors.append(f"{path}: forbidden Stage 4 umbrella type reference: {needle}")

fail(errors)
print("Stage 4 umbrella-type guard passed.")
