# Changes from Stratix and CloudNow (to Cirrus)

This document outlines the major architectural and design changes made to combine **Stratix** (the native Apple TV client for Xbox Game Pass/xCloud cloud gaming) and **CloudNow** (the native Apple TV client for NVIDIA GeForce NOW) into the unified combined client **Cirrus**.

## 1. Project Structure & Integration
- **Unified Workspace**: Replaced separate Xcode configurations (`Stratix.xcworkspace` and `CloudNow.xcodeproj`) with a single, multi-platform workspace mapping both macOS and tvOS targets.
- **Unified Launch Pipeline**: Created `CloudNowApp.swift` as a single main entry point that injects both `AuthManager` (GFN state) and `AppCoordinator` (Xbox/Stratix state) environments.
- **Combined Shell**: Wired the top-level navigation container in `AuthenticatedShellView.swift` to load the unified `CloudLibraryView`.

## 2. User Interface & Navigation
- **Unified Browse Experience**: Merged the Xbox library view and GeForce NOW game library grids into a unified dashboard.
- **Lightweight Top Navigation Capsules**: Implemented a modern, layout-neutral navigation bar styling at the top of the shell with custom rounded capsules for profile stats, navigation tabs, and system status metrics.
- **Integrated Settings Suite**: Redesigned the settings interface inside `CloudLibrarySettingsView.swift` to group configuration cards for Xbox Cloud Gaming (stream resolution, FPS, diagnostics), GeForce NOW (target FPS, resolution, custom bitrates), and General/Accessibility parameters.

## 3. Streaming Experience Improvements
- **Xbox Stream Loading Screen Blur**: Added a high-end backdrop blur effect to the xCloud connecting view to match GFN stream transition aesthetics.
- **Background Catalog Caching & Refreshing**: Implemented background token refresh cycles and local GFN game catalogs caching to eliminate 20-second startup delay screens.
- **Non-blocking Refresh Indicators**: Replaced full-screen block screens with localized, rotating spinning loaders next to service headers when syncing catalog updates.

## 4. Performance & Hardening
- **Upscaler Default Configuration**: Disabled streaming upscaling by default (`upscalingEnabled = false` in `SettingsStore.swift`) to protect older hardware from frame drops, leaving it optional via settings.
- **Onboarding Cleanup**: Removed tutorial card overlays, focus indicators, and onboarding walkthrough tour dependencies from both the shell view and settings view to allow immediate app navigation.
- **Liquid Glass Rendering Fixes**: Replaced unstable `ZStack` background layers with native SwiftUI shape background bindings (`.background(.style, in: Shape)`) to eliminate vertical layout stretching on navigation bars, guide overlays, and diagnostics panels.
