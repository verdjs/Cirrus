#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, read_text, line_count, fail

errors: list[str] = []

required_paths = [
    rel("Packages/CloudXModels/Sources/CloudXModels/Models.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRenderer+PlainPipeline.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRenderer+Lifecycle.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImpl+Stats.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImpl+DataChannels.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImpl+TVOSAudio.swift"),
]
errors.extend(require_paths(required_paths))

models_swift = rel("Packages/CloudXModels/Sources/CloudXModels/Models.swift")
if models_swift.exists():
    text = read_text(models_swift)

    if line_count(models_swift) > 200:
        errors.append(
            f"{models_swift}: expected Models.swift to remain a shim-style file; line count is {line_count(models_swift)}"
        )

    forbidden_decls = ["struct ", "enum ", "final class ", "actor "]
    decl_hits = []
    for needle in forbidden_decls:
        if needle in text:
            decl_hits.append(needle)

    if decl_hits:
        errors.append(
            f"{models_swift}: expected no real type definitions in Models.swift; found declaration markers {decl_hits}"
        )

fail(errors)
print("Stage 1 decomposition floor guard passed.")
