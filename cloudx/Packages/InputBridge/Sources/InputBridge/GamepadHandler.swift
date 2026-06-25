// GamepadHandler.swift
// Defines gamepad handler.
//

import Foundation
import CloudXModels
import GameController
import CoreHaptics

/// Stream-level shortcuts that the input layer can synthesize from controller chords.
public enum ShortcutAction: Sendable, Equatable {
    case toggleStatsHUD
    case toggleStreamMenu
    case disconnectStream
    case muteToggle
}

/// Describes a held-button combination that should emit a single shortcut action.
public struct ChordDefinition: Sendable {
    public let buttons: GamepadButtons
    public let holdDurationMs: Int
    public let action: ShortcutAction

    public init(buttons: GamepadButtons, holdDurationMs: Int, action: ShortcutAction) {
        self.buttons = buttons
        self.holdDurationMs = holdDurationMs
        self.action = action
    }
}

/// Tracks chord hold timing so one shortcut fires once per sustained press sequence.
public struct ChordRecognizer: Sendable {
    private var startedAt: [ShortcutAction: TimeInterval] = [:]
    private var fired: Set<ShortcutAction> = []
    public var definitions: [ChordDefinition]

    public init(definitions: [ChordDefinition]) {
        self.definitions = definitions
    }

    /// Evaluates the latest input frame and returns any newly triggered shortcut actions.
    public mutating func process(frame: GamepadInputFrame) -> [ShortcutAction] {
        var actions: [ShortcutAction] = []
        let now = ProcessInfo.processInfo.systemUptime

        for definition in definitions {
            let matched = frame.buttons.contains(definition.buttons)
            if matched {
                let start = startedAt[definition.action] ?? now
                startedAt[definition.action] = start
                let elapsedMs = Int((now - start) * 1000)
                if !fired.contains(definition.action) && elapsedMs >= max(0, definition.holdDurationMs) {
                    actions.append(definition.action)
                    fired.insert(definition.action)
                }
            } else {
                startedAt.removeValue(forKey: definition.action)
                fired.remove(definition.action)
            }
        }
        return actions
    }
}

// MARK: - Input Frame Builder from GCController

/// Reads physical gamepad state from GCExtendedGamepad and converts it
/// into the binary GamepadInputFrame used by the Xbox input protocol.
///
/// Mirrors gamepad.ts getGamepadState() and getDefaultFamepadFrame().
@MainActor
public final class GamepadHandler {

    enum TriggerSide {
        case left
        case right
    }

    private enum ResolvedTriggerMode {
        case analogOnly
        case digitalFallback
    }

    public let gamepadIndex: UInt8

    /// The physical GCController this handler drives. Used for haptics.
    /// Weak ref — the controller is owned by GameController framework.
    public weak var controller: GCController? {
        didSet {
            stopAllHaptics()
            configureAdaptiveTriggers()
        }
    }

    /// Keep haptic engines alive per-locality; short-lived engines can drop pulses on some controllers.
    private var hapticEnginesByLocality: [String: CHHapticEngine] = [:]
    /// Keep track of active players per locality to stop them instantly when intensity drops or updates.
    private var activeHapticPlayersByLocality: [String: CHHapticPatternPlayer] = [:]

    private var leftTriggerAutoMode: ResolvedTriggerMode = .analogOnly
    private var rightTriggerAutoMode: ResolvedTriggerMode = .analogOnly
    /// Runtime-tunable input preferences applied to trigger interpretation and haptic scaling.
    public var settings = ControllerSettings() {
        didSet {
            configureAdaptiveTriggers()
        }
    }

    public init(gamepadIndex: UInt8 = 0) {
        self.gamepadIndex = gamepadIndex
    }

    // MARK: - Read frame from GCExtendedGamepad

    /// Call this at ~60 Hz from a timer/display-link.
    /// Accepts a ControllerSettings value so user prefs (deadzone, invertY, swapAB,
    /// triggerSensitivity) are applied per-frame without any global state.
    public func readFrame(from gamepad: GCExtendedGamepad, settings: ControllerSettings = ControllerSettings()) -> GamepadInputFrame {
        var buttons = GamepadButtons()

        // Face buttons (default/original mapping)
        if gamepad.buttonA.isPressed { buttons.insert(.a) }
        if gamepad.buttonB.isPressed { buttons.insert(.b) }
        if gamepad.buttonX.isPressed { buttons.insert(.x) }
        if gamepad.buttonY.isPressed { buttons.insert(.y) }

        // Shoulders
        if gamepad.leftShoulder.isPressed  { buttons.insert(.leftShoulder) }
        if gamepad.rightShoulder.isPressed { buttons.insert(.rightShoulder) }

        // Thumbstick clicks
        if gamepad.leftThumbstickButton?.isPressed == true  { buttons.insert(.leftThumb) }
        if gamepad.rightThumbstickButton?.isPressed == true { buttons.insert(.rightThumb) }

        // D-pad
        if gamepad.dpad.up.isPressed    { buttons.insert(.dpadUp) }
        if gamepad.dpad.down.isPressed  { buttons.insert(.dpadDown) }
        if gamepad.dpad.left.isPressed  { buttons.insert(.dpadLeft) }
        if gamepad.dpad.right.isPressed { buttons.insert(.dpadRight) }

        // Menu / View
        let menuPressed = gamepad.buttonMenu.isPressed
        var viewPressed = gamepad.buttonOptions?.isPressed ?? false

        // PS5 DualSense & PS4 DualShock touchpad click -> View button (Select/Back)
        if let dualSense = gamepad as? GCDualSenseGamepad, dualSense.touchpadButton.isPressed {
            viewPressed = true
        } else if let dualShock = gamepad as? GCDualShockGamepad, dualShock.touchpadButton.isPressed {
            viewPressed = true
        }

        if menuPressed { buttons.insert(.menu) }
        if viewPressed { buttons.insert(.view) }

        // PS button / Home button -> Guide button (Nexus)
        if let home = gamepad.buttonHome, home.isPressed {
            buttons.insert(.nexus)
        }

        // Swap A and B face buttons if the user configured it
        if settings.swapAB {
            let hasA = buttons.contains(.a)
            let hasB = buttons.contains(.b)
            if hasA  { buttons.insert(.b)  } else { buttons.remove(.b) }
            if hasB  { buttons.insert(.a)  } else { buttons.remove(.a) }
        }

        // Triggers (analog 0–1) scaled by triggerSensitivity.
        // A sensitivity of 0.5 means a half-pull already outputs 1.0 (hair trigger).
        let ltRaw = resolveTriggerRaw(
            rawValue: gamepad.leftTrigger.value,
            isPressed: gamepad.leftTrigger.isPressed,
            side: .left,
            settings: settings
        )
        let rtRaw = resolveTriggerRaw(
            rawValue: gamepad.rightTrigger.value,
            isPressed: gamepad.rightTrigger.isPressed,
            side: .right,
            settings: settings
        )
        let sensitivity = max(settings.triggerSensitivity, 0.01)
        let lt = min(ltRaw / sensitivity, 1.0)
        let rt = min(rtRaw / sensitivity, 1.0)

        // Thumbsticks with user-configured deadzone
        let lx = applyDeadzone(gamepad.leftThumbstick.xAxis.value, deadzone: settings.deadzone)
        // GameController uses up=+1, while browser Gamepad/xCloud uses up=-1.
        // Normalize to browser semantics first so the protocol matches the JS client.
        var ly = -applyDeadzone(gamepad.leftThumbstick.yAxis.value, deadzone: settings.deadzone)
        let rx = applyDeadzone(gamepad.rightThumbstick.xAxis.value, deadzone: settings.deadzone)
        var ry = -applyDeadzone(gamepad.rightThumbstick.yAxis.value, deadzone: settings.deadzone)

        // Optional user invert is applied after baseline normalization.
        if settings.invertY {
            ly = -ly
            ry = -ry
        }

        return GamepadInputFrame(
            gamepadIndex: gamepadIndex,
            buttons: buttons,
            leftThumb: SIMD2(lx, ly),
            rightThumb: SIMD2(rx, ry),
            triggers: SIMD2(lt, rt)
        )
    }

    private func applyDeadzone(_ value: Float, deadzone: Float) -> Float {
        let abs = Swift.abs(value)
        guard abs >= deadzone else { return 0 }
        let sign: Float = value >= 0 ? 1 : -1
        // Rescale remaining range to 0–1
        return sign * (abs - deadzone) / (1.0 - max(deadzone, 0.0001))
    }

    /// Resolves the outgoing trigger value according to the caller's compatibility mode.
    func resolveTriggerRaw(
        rawValue: Float,
        isPressed: Bool,
        side: TriggerSide,
        settings: ControllerSettings
    ) -> Float {
        let clampedRaw = max(0, min(rawValue, 1))

        switch settings.triggerInterpretationMode {
        case .analogOnly:
            return clampedRaw
        case .digitalFallback:
            return max(clampedRaw, isPressed ? 1.0 : 0.0)
        case .auto:
            return resolveAutoTriggerRaw(clampedRaw, isPressed: isPressed, side: side)
        }
    }

    /// Learns whether a trigger behaves like a true analog axis or only a digital button.
    private func resolveAutoTriggerRaw(_ raw: Float, isPressed: Bool, side: TriggerSide) -> Float {
        let digitalPressedEpsilon: Float = 0.02
        let analogEvidenceMin: Float = 0.05
        let analogEvidenceMax: Float = 0.95

        var mode = side == .left ? leftTriggerAutoMode : rightTriggerAutoMode

        // Intermediate analog travel is strong evidence that fallback should stay disabled.
        if raw > analogEvidenceMin && raw < analogEvidenceMax {
            mode = .analogOnly
        } else if isPressed && raw <= digitalPressedEpsilon {
            // Some digital-trigger controllers report pressed state without analog value.
            mode = .digitalFallback
        }

        if side == .left {
            leftTriggerAutoMode = mode
        } else {
            rightTriggerAutoMode = mode
        }

        switch mode {
        case .analogOnly:
            return raw
        case .digitalFallback:
            return max(raw, isPressed ? 1.0 : 0.0)
        }
    }

    // MARK: - Siri Remote as minimal gamepad

    /// Translate Siri Remote micro-gamepad to a minimal gamepad frame.
    /// Used when no physical controller is connected.
    public func readFrameFromMicroGamepad(_ micro: GCMicroGamepad) -> GamepadInputFrame {
        var buttons = GamepadButtons()
        if micro.buttonA.isPressed { buttons.insert(.a) }
        if micro.buttonX.isPressed { buttons.insert(.b) }
        if micro.dpad.up.isPressed    { buttons.insert(.dpadUp) }
        if micro.dpad.down.isPressed  { buttons.insert(.dpadDown) }
        if micro.dpad.left.isPressed  { buttons.insert(.dpadLeft) }
        if micro.dpad.right.isPressed { buttons.insert(.dpadRight) }
        if micro.buttonMenu.isPressed { buttons.insert(.menu) }

        return GamepadInputFrame(
            gamepadIndex: gamepadIndex,
            buttons: buttons,
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
    }

    // MARK: - Haptics / Rumble

    /// Stops all currently active haptic players.
    public func stopAllHaptics() {
        for player in activeHapticPlayersByLocality.values {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        activeHapticPlayersByLocality.removeAll()
    }

    /// Configures adaptive triggers on DualSense controllers according to the selected mode.
    public func configureAdaptiveTriggers() {
        guard let dualSense = controller?.extendedGamepad as? GCDualSenseGamepad else { return }
        
        switch settings.adaptiveTriggersMode {
        case .off:
            dualSense.leftTrigger.setModeOff()
            dualSense.rightTrigger.setModeOff()
        case .feedback:
            dualSense.leftTrigger.setModeFeedbackWithStartPosition(0.1, resistiveStrength: 0.5)
            dualSense.rightTrigger.setModeFeedbackWithStartPosition(0.1, resistiveStrength: 0.5)
        case .weapon:
            dualSense.leftTrigger.setModeWeaponWithStartPosition(0.2, endPosition: 0.8, resistiveStrength: 0.7)
            dualSense.rightTrigger.setModeWeaponWithStartPosition(0.2, endPosition: 0.8, resistiveStrength: 0.7)
        case .gameplay:
            // Dynamic vibration mapping is driven by incoming VibrationReports in sendHaptics
            dualSense.leftTrigger.setModeOff()
            dualSense.rightTrigger.setModeOff()
        }
    }

    /// Send a vibration report to the physical controller via GCDeviceHaptics + CoreHaptics.
    /// Silently ignores controllers that don't support haptics (older controllers, Apple TV remote).
    /// Supports left/right handles (all rumble controllers) and left/right triggers (PS5 DualSense).
    public func sendHaptics(from report: VibrationReport) {
        let verboseInputLogs = UserDefaults.standard.object(forKey: "debug.input.verbose_logs") as? Bool ?? false
        
        // 1. Dynamic Trigger Vibration for DualSense in gameplay mode
        if let dualSense = controller?.extendedGamepad as? GCDualSenseGamepad, settings.adaptiveTriggersMode == .gameplay {
            let leftVal = report.leftTriggerMotorPercent * settings.vibrationIntensity
            let rightVal = report.rightTriggerMotorPercent * settings.vibrationIntensity
            
            if leftVal > 0.01 {
                dualSense.leftTrigger.setModeVibrationWithStartPosition(0.0, amplitude: leftVal, frequency: 0.5)
            } else {
                dualSense.leftTrigger.setModeOff()
            }
            
            if rightVal > 0.01 {
                dualSense.rightTrigger.setModeVibrationWithStartPosition(0.0, amplitude: rightVal, frequency: 0.5)
            } else {
                dualSense.rightTrigger.setModeOff()
            }
        }

        guard let haptics = controller?.haptics else {
            if verboseInputLogs {
                print("[GamepadHaptics] controller has no haptics interface; skipping vibration")
            }
            return
        }

        let durationSec = report.durationMs > 0 ? TimeInterval(report.durationMs) / 1000.0 : 0.12
        let supportedLocalities = haptics.supportedLocalities
        if verboseInputLogs {
            let names = supportedLocalities.map(\.rawValue).sorted().joined(separator: ",")
            print("[GamepadHaptics] supported localities=\(names)")
        }

        var pairs: [(GCHapticsLocality, Float)] = [
            (.leftHandle,   report.leftMotorPercent),
            (.rightHandle,  report.rightMotorPercent),
        ]
        
        // Prevent trigger core haptics conflicts when adaptive triggers are in resistive feedback or weapon modes.
        if settings.adaptiveTriggersMode == .gameplay || settings.adaptiveTriggersMode == .off {
            pairs.append((.leftTrigger,  report.leftTriggerMotorPercent))
            pairs.append((.rightTrigger, report.rightTriggerMotorPercent))
        }

        var playedAnyLocality = false
        for (locality, intensity) in pairs {
            let key = locality.rawValue
            let scaledIntensity = max(0, min(1, intensity * settings.vibrationIntensity))
            
            if scaledIntensity <= 0.01 {
                if let activePlayer = activeHapticPlayersByLocality[key] {
                    try? activePlayer.stop(atTime: CHHapticTimeImmediate)
                    activeHapticPlayersByLocality.removeValue(forKey: key)
                }
                continue
            }
            
            guard supportedLocalities.contains(locality) else { continue }
            
            // Instantly stop existing player for this locality to prevent rumble overlapping
            if let activePlayer = activeHapticPlayersByLocality[key] {
                try? activePlayer.stop(atTime: CHHapticTimeImmediate)
                activeHapticPlayersByLocality.removeValue(forKey: key)
            }
            
            playedAnyLocality = playHaptics(
                locality: locality,
                intensity: scaledIntensity,
                durationSec: durationSec,
                haptics: haptics,
                verboseInputLogs: verboseInputLogs
            ) || playedAnyLocality
        }

        // Some controllers expose only default/all locality routing on tvOS.
        // Fall back to .default so DS4/Xbox still rumble even without split localities.
        let defaultKey = GCHapticsLocality.default.rawValue
        if !playedAnyLocality {
            let fallbackIntensityRaw = max(
                report.leftMotorPercent,
                report.rightMotorPercent,
                report.leftTriggerMotorPercent,
                report.rightTriggerMotorPercent
            )
            let fallbackIntensity = max(0, min(1, fallbackIntensityRaw * settings.vibrationIntensity))
            if fallbackIntensity <= 0.01 {
                if let activePlayer = activeHapticPlayersByLocality[defaultKey] {
                    try? activePlayer.stop(atTime: CHHapticTimeImmediate)
                    activeHapticPlayersByLocality.removeValue(forKey: defaultKey)
                }
            } else {
                if let activePlayer = activeHapticPlayersByLocality[defaultKey] {
                    try? activePlayer.stop(atTime: CHHapticTimeImmediate)
                    activeHapticPlayersByLocality.removeValue(forKey: defaultKey)
                }
                _ = playHaptics(
                    locality: .default,
                    intensity: fallbackIntensity,
                    durationSec: durationSec,
                    haptics: haptics,
                    verboseInputLogs: verboseInputLogs,
                    logPrefix: "fallback "
                )
            }
        } else {
            // Clean up fallback default player if specific handles/triggers are playing
            if let activePlayer = activeHapticPlayersByLocality[defaultKey] {
                try? activePlayer.stop(atTime: CHHapticTimeImmediate)
                activeHapticPlayersByLocality.removeValue(forKey: defaultKey)
            }
        }
    }

    private func playHaptics(
        locality: GCHapticsLocality,
        intensity: Float,
        durationSec: TimeInterval,
        haptics: GCDeviceHaptics,
        verboseInputLogs: Bool,
        logPrefix: String = ""
    ) -> Bool {
        guard let engine = hapticEngine(
            for: locality,
            haptics: haptics,
            verboseInputLogs: verboseInputLogs
        ) else {
            return false
        }

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: durationSec
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else {
            return false
        }

        do {
            try engine.start()
        } catch {
            if verboseInputLogs {
                print("[GamepadHaptics] failed start locality=\(locality.rawValue) error=\(error.localizedDescription)")
            }
            return false
        }

        do {
            try player.start(atTime: CHHapticTimeImmediate)
            activeHapticPlayersByLocality[locality.rawValue] = player
        } catch {
            if verboseInputLogs {
                print("[GamepadHaptics] failed start player for locality=\(locality.rawValue) error=\(error.localizedDescription)")
            }
            return false
        }
        
        if verboseInputLogs {
            print("[GamepadHaptics] \(logPrefix)played locality=\(locality.rawValue) intensity=\(String(format: "%.2f", intensity)) duration=\(String(format: "%.2f", durationSec))s")
        }
        return true
    }

    private func hapticEngine(
        for locality: GCHapticsLocality,
        haptics: GCDeviceHaptics,
        verboseInputLogs: Bool
    ) -> CHHapticEngine? {
        let key = locality.rawValue
        if let existing = hapticEnginesByLocality[key] {
            return existing
        }
        guard let created = haptics.createEngine(withLocality: locality) else {
            if verboseInputLogs {
                print("[GamepadHaptics] failed createEngine locality=\(locality.rawValue)")
            }
            return nil
        }
        hapticEnginesByLocality[key] = created
        if verboseInputLogs {
            print("[GamepadHaptics] created engine locality=\(locality.rawValue)")
        }
        return created
    }

    // MARK: - Null frame (no input)

    /// Returns a neutral frame for idle polling when no buttons or sticks are active.
    public func idleFrame() -> GamepadInputFrame {
        GamepadInputFrame(
            gamepadIndex: gamepadIndex,
            buttons: [],
            leftThumb: .zero,
            rightThumb: .zero,
            triggers: .zero
        )
    }
}
