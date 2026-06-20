#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, assert_contains, assert_not_contains, fail, read_text

errors: list[str] = []

app_project = rel("Apps/CloudX/CloudX.xcodeproj/project.pbxproj")
protocol_file = rel("Packages/CloudXCore/Sources/CloudXCore/App/Composition/AppControllerProtocols.swift")
services_file = rel("Packages/CloudXCore/Sources/CloudXCore/App/Composition/AppControllerServices.swift")
dependency_builder = rel("Packages/CloudXCore/Sources/CloudXCore/App/Composition/AppControllerBuilder.swift")
dependency_graph = rel("Packages/CloudXCore/Sources/CloudXCore/App/Composition/AppControllerGraph.swift")
library_warmup = rel("Packages/CloudXCore/Sources/CloudXCore/LibraryPostLoadWarmupCoordinator.swift")
app_coordinator = rel("Packages/CloudXCore/Sources/CloudXCore/App/AppCoordinator.swift")

errors.extend(require_paths([
    protocol_file,
    services_file,
    dependency_builder,
    dependency_graph,
    library_warmup,
    app_project,
]))

errors.extend(assert_contains(protocol_file, [
    "protocol ConsoleControllerDependencies: AnyObject",
    "protocol ProfileControllerDependencies: AnyObject",
    "protocol AchievementsControllerDependencies: AnyObject",
    "protocol LibraryControllerDependencies: AnyObject, Sendable",
    "protocol InputControllerDependencies: AnyObject",
    "protocol StreamControllerDependencies: AnyObject, Sendable",
]))

errors.extend(assert_contains(services_file, [
    "extension SessionController: ConsoleControllerDependencies",
    "final class AppProfileControllerServices: ProfileControllerDependencies",
    "final class AppAchievementsControllerServices: AchievementsControllerDependencies",
    "final class AppLibraryControllerServices: LibraryControllerDependencies",
    "extension StreamController: InputControllerDependencies",
    "final class AppStreamControllerServices: StreamControllerDependencies",
]))

errors.extend(assert_contains(dependency_builder, [
    "AppProfileControllerServices(",
    "AppAchievementsControllerServices(",
    "AppLibraryControllerServices(",
    "AppStreamControllerServices(",
]))

errors.extend(assert_contains(app_coordinator, [
    "libraryController.attach(libraryControllerServices)",
    "profileController.attach(profileControllerServices)",
    "consoleController.attach(sessionController)",
    "streamController.attach(streamControllerServices)",
    "inputController.attach(streamController)",
    "achievementsController.attach(achievementsControllerServices)",
]))

errors.extend(assert_not_contains(services_file, [
    "final class AppConsoleControllerServices",
    "final class AppInputControllerServices",
]))

errors.extend(assert_not_contains(dependency_builder, [
    "AppConsoleControllerServices(",
    "AppInputControllerServices(",
]))

errors.extend(assert_not_contains(dependency_graph, [
    "consoleControllerServices",
    "inputControllerServices",
]))

errors.extend(assert_contains(library_warmup, [
    "struct LibraryPostLoadWarmupEnvironment",
    "let loadCurrentUserProfile: @Sendable @MainActor () async -> Void",
    "let loadSocialPeople: @Sendable @MainActor (Int) async -> Void",
]))
errors.extend(assert_not_contains(library_warmup, [
    "AppCoordinator",
    "coordinator:",
]))

errors.extend(assert_not_contains(app_project, [
    "DesignSystemTV in Frameworks",
    'XCLocalSwiftPackageReference "../../Packages/DesignSystemTV"',
    "productName = DesignSystemTV;",
]))

for path in [
    rel("Apps/CloudX/Sources/CloudX"),
    rel("Apps/CloudX/CloudXTests"),
    rel("Apps/CloudX/CloudXUITests"),
    rel("Apps/CloudX/CloudXPerformanceTests"),
    rel("Apps/CloudX/CloudXPerformanceUITests"),
]:
    if path.is_dir():
        for source in path.rglob("*.swift"):
            errors.extend(assert_not_contains(source, ["import DesignSystemTV"]))

for path in [
    rel("Packages/CloudXCore/Sources/CloudXCore/ConsoleController.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Profile/ProfileController.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/AchievementsController.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/LibraryController.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/InputController.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/StreamController.swift"),
]:
    errors.extend(assert_not_contains(path, [
        "weak var coordinator",
        "AppCoordinator",
        "coordinator?.",
        "coordinator.",
        "attach(_ coordinator: AppCoordinator)",
    ]))

for legacy in [
    rel("Packages/CloudXCore/Sources/CloudXCore/App/AppControllerDependencies.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/App/AppControllerBuilder.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/App/AppControllerGraph.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/Streaming/StreamControllerEnvironmentFactory.swift"),
    rel("Packages/CloudXCore/Sources/CloudXCore/App/Composition/AppControllerDependencies.swift"),
]:
    if legacy.exists():
        errors.append(f"{legacy}: legacy Stage 7 root-path dependency seam file must not remain.")

usage_requirements = {
    "ConsoleControllerDependencies": 3,
    "ProfileControllerDependencies": 3,
    "AchievementsControllerDependencies": 3,
    "LibraryControllerDependencies": 4,
    "InputControllerDependencies": 3,
    "StreamControllerDependencies": 4,
    "AppProfileControllerServices": 3,
    "AppAchievementsControllerServices": 3,
    "AppLibraryControllerServices": 4,
    "AppStreamControllerServices": 4,
}

search_roots = [
    rel("Packages/CloudXCore/Sources/CloudXCore"),
    rel("Packages/CloudXCore/Tests/CloudXCoreTests"),
]

swift_texts = [
    read_text(path)
    for root in search_roots
    for path in sorted(root.rglob("*.swift"))
]

for needle, minimum in usage_requirements.items():
    count = sum(text.count(needle) for text in swift_texts)
    if count < minimum:
        errors.append(
            f"{needle}: expected first-party usage count >= {minimum}, found {count}"
        )

legacy_guard = rel("Tools/ci/check_stage7_dependency_seams.py")
if legacy_guard.exists():
    errors.append(f"{legacy_guard}: duplicate weaker Stage 7 guard must not remain.")

fail(errors)
print("Stage 7 package boundary guard passed.")
