#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, read_text, line_count, fail

errors: list[str] = []

required_paths = [
    rel("Packages/CloudXModels/Sources/CloudXModels/Achievements/AchievementModels.swift"),
    rel("Packages/CloudXModels/Sources/CloudXModels/CloudLibrary/CloudLibraryModels.swift"),
    rel("Packages/CloudXModels/Sources/CloudXModels/Identifiers/ProductID.swift"),
    rel("Packages/CloudXModels/Sources/CloudXModels/Identifiers/TitleID.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRendererPlainPipeline.swift"),
    rel("Apps/CloudX/Sources/CloudX/Features/Streaming/Rendering/SampleBufferDisplayRendererLifecycle.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImplStats.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImplDataChannels.swift"),
    rel("Apps/CloudX/Sources/CloudX/Integration/WebRTC/WebRTCClientImplTVOSAudio.swift"),
]
errors.extend(require_paths(required_paths))

fail(errors)
print("Stage 1 decomposition floor guard passed.")
