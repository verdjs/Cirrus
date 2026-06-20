// CloudLibrarySettingsBindings.swift
// Defines cloud library settings bindings for the CloudLibrary / Settings surface.
//

import SwiftUI
import CloudXCore
import CloudXModels

enum CloudLibrarySettingsBindings {
    static func resolvedPane(
        currentPane: CloudLibrarySettingsPane,
        storedRawValue: String,
        isAdvancedMode: Bool,
        restoreStoredSelection: Bool
    ) -> CloudLibrarySettingsPane {
        let visiblePanes = CloudLibrarySettingsPane.visibleCases(isAdvanced: isAdvancedMode)
        let storedPane = CloudLibrarySettingsPane(rawValue: storedRawValue)

        if restoreStoredSelection, let storedPane, visiblePanes.contains(storedPane) {
            return storedPane
        }
        if visiblePanes.contains(currentPane) {
            return currentPane
        }
        return storedPane.flatMap { visiblePanes.contains($0) ? $0 : nil } ?? visiblePanes.first ?? .overview
    }
}

extension CloudLibrarySettingsView {
    var triggerModeBinding: Binding<String> {
        Binding(
            get: { settingsStore.controller.triggerInterpretationMode.rawValue },
            set: { newValue in
                guard let mode = CloudXModels.ControllerSettings.TriggerInterpretationMode(rawValue: newValue) else {
                    return
                }
                var next = settingsStore.controller
                next.triggerInterpretationMode = mode
                settingsStore.controller = next
            }
        )
    }

    func shellBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ShellSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.shell[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.shell
                next[keyPath: keyPath] = newValue
                settingsStore.shell = next
            }
        )
    }

    func streamBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.StreamSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.stream[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.stream
                next[keyPath: keyPath] = newValue
                settingsStore.stream = next
            }
        )
    }

    var diagnosticsFloorBehaviorBinding: Binding<String> {
        Binding(
            get: { settingsStore.diagnostics.upscalingFloorBehavior.label },
            set: { newValue in
                guard let behavior = UpscalingFloorBehavior.allCases.first(where: { $0.label == newValue }) else {
                    return
                }
                var next = settingsStore.diagnostics
                next.upscalingFloorBehavior = behavior
                settingsStore.diagnostics = next
            }
        )
    }

    func controllerBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.ControllerSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.controller[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.controller
                next[keyPath: keyPath] = newValue
                settingsStore.controller = next
            }
        )
    }

    func accessibilityBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.AccessibilitySettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.accessibility[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.accessibility
                next[keyPath: keyPath] = newValue
                settingsStore.accessibility = next
            }
        )
    }

    func diagnosticsBinding<Value>(_ keyPath: WritableKeyPath<SettingsStore.DiagnosticsSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.diagnostics[keyPath: keyPath] },
            set: { newValue in
                var next = settingsStore.diagnostics
                next[keyPath: keyPath] = newValue
                settingsStore.diagnostics = next
            }
        )
    }

    var upscalingModeBinding: Binding<String> {
        Binding(
            get: {
                if !settingsStore.stream.upscalingEnabled {
                    return "Off"
                }
                let rendererMode = UserDefaults.standard.string(forKey: "guide.renderer_mode") ?? "metalCAS"
                if rendererMode == "sampleBuffer" {
                    return "Off"
                }
                if rendererMode == "metalCAS" {
                    return "AMD FSR / CAS (Sharp)"
                }
                if settingsStore.diagnostics.upscalingFloorBehavior == .sampleFloor {
                    return "MetalFX Spatial"
                }
                return "Apple Super Resolution"
            },
            set: { newValue in
                var nextStream = settingsStore.stream
                var nextDiag = settingsStore.diagnostics
                
                switch newValue {
                case "Off":
                    nextStream.upscalingEnabled = false
                    UserDefaults.standard.set("sampleBuffer", forKey: "guide.renderer_mode")
                case "MetalFX Spatial":
                    nextStream.upscalingEnabled = true
                    nextDiag.upscalingFloorBehavior = .sampleFloor
                    UserDefaults.standard.set("auto", forKey: "guide.renderer_mode")
                    UserDefaults.standard.set(0.0, forKey: "guide.sharpness")
                case "AMD FSR / CAS (Sharp)":
                    nextStream.upscalingEnabled = true
                    nextDiag.upscalingFloorBehavior = .metalFloor
                    UserDefaults.standard.set("metalCAS", forKey: "guide.renderer_mode")
                    UserDefaults.standard.set(0.8, forKey: "guide.sharpness")
                case "Apple Super Resolution":
                    nextStream.upscalingEnabled = true
                    nextDiag.upscalingFloorBehavior = .metalFloor
                    UserDefaults.standard.set("auto", forKey: "guide.renderer_mode")
                    UserDefaults.standard.set(0.0, forKey: "guide.sharpness")
                default:
                    break
                }
                
                settingsStore.stream = nextStream
                settingsStore.diagnostics = nextDiag
            }
        )
    }
}
