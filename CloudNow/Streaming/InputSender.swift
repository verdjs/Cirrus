import Foundation
import GameController
import CoreHaptics

// MARK: - GFN Input Protocol Constants

private enum GFNInput {
    static let keyDown: UInt8      = 3
    static let keyUp: UInt8        = 4
    static let mouseRel: UInt8     = 7
    static let mouseBtnDown: UInt8 = 8
    static let mouseBtnUp: UInt8   = 9
    static let mouseWheel: UInt8   = 10
    static let gamepad: UInt8      = 12
    // Heartbeat type (u32 LE value 2) — keeps the server's virtual gamepad alive
    static let heartbeatU32: UInt32 = 2

    // Gamepad packet: 38 bytes, u32 LE type per GFN protocol
    static let gamepadPacketSize = 38
    // Keyboard/mouse packets use 4-byte UInt32 LE type (matches TS InputEncoder)
    static let keyboardPacketSize    = 18
    static let mouseButtonPacketSize = 18
    static let mouseMovePacketSize   = 22
    static let mouseWheelPacketSize  = 22

    // XInput button flags
    static let dpadUp: UInt16    = 0x0001
    static let dpadDown: UInt16  = 0x0002
    static let dpadLeft: UInt16  = 0x0004
    static let dpadRight: UInt16 = 0x0008
    static let start: UInt16     = 0x0010
    static let back: UInt16      = 0x0020
    static let ls: UInt16        = 0x0040
    static let rs: UInt16        = 0x0080
    static let lb: UInt16        = 0x0100
    static let rb: UInt16        = 0x0200
    static let guide: UInt16     = 0x0400
    static let buttonA: UInt16   = 0x1000
    static let buttonB: UInt16   = 0x2000
    static let buttonX: UInt16   = 0x4000
    static let buttonY: UInt16   = 0x8000
}

// MARK: - Remote Input Mode

enum RemoteInputMode: String, Codable, Equatable {
    case mouse
    case gamepad
    case dualsense
}

// MARK: - Input Event Handler

/// Implemented by InputSender; adopted by VideoSurfaceView to forward keyboard/mouse events.
protocol InputEventHandler: AnyObject {
    func sendKeyEvent(down: Bool, vk: UInt16, scancode: UInt16, modifiers: UInt16)
    func sendMouseMove(dx: Int16, dy: Int16)
    func sendMouseButton(down: Bool, button: UInt8)
    func sendMouseWheel(delta: Int16)
}

// MARK: - Input Encoder

/// Encodes controller and HID input into GFN binary protocol packets.
/// Supports protocol v2 (plain) and v3 (wrapped with 0x23 timestamp header).
final class InputEncoder {
    private var protocolVersion = 2
    private var gamepadSequence = [Int: UInt16]()

    func setProtocolVersion(_ v: Int) { protocolVersion = v }

    // MARK: - Heartbeat

    /// Sends a keep-alive to hold the server's virtual gamepad state between real input events.
    /// Encoded as a raw 4-byte u32 LE value 2 — no v3 wrapper (matches official client's Jc()).
    func encodeHeartbeat() -> Data {
        var buf = Data(count: 4)
        writeUInt32LE(&buf, offset: 0, value: GFNInput.heartbeatU32)
        return buf
    }

    // MARK: - Haptics Advertisement

    /// Encodes a haptics capability advertisement packet (INPUT_HAPTICS_ENABLED = 13).
    func encodeHapticsEnabled(_ enabled: Bool) -> Data {
        var buf = Data(count: 6)
        writeUInt32LE(&buf, offset: 0, value: 13)
        writeUInt16BE(&buf, offset: 4, value: enabled ? 1 : 0)
        return wrapSingleEvent(buf)
    }

    // MARK: Gamepad

    /// Encodes a gamepad state packet.
    /// - Parameter gamepadBitmap: Bitmask of connected controller slots (bit i = controller i active).
    func encodeGamepad(
        controllerId: Int,
        buttons: UInt16,
        leftTrigger: UInt8,
        rightTrigger: UInt8,
        leftStickX: Int16,
        leftStickY: Int16,
        rightStickX: Int16,
        rightStickY: Int16,
        gamepadBitmap: UInt16
    ) -> Data {
        var buf = Data(count: GFNInput.gamepadPacketSize)
        writeUInt32LE(&buf, offset: 0,  value: 12)                        // type
        writeUInt16LE(&buf, offset: 4,  value: 26)                        // payload size
        writeUInt16LE(&buf, offset: 6,  value: UInt16(controllerId & 3))  // gamepad index
        writeUInt16LE(&buf, offset: 8,  value: gamepadBitmap)             // connected-controller bitmask
        writeUInt16LE(&buf, offset: 10, value: 20)                        // inner payload size
        writeUInt16LE(&buf, offset: 12, value: buttons)                   // XInput buttons
        buf[14] = leftTrigger
        buf[15] = rightTrigger
        writeInt16LE(&buf, offset: 16, value: leftStickX)
        writeInt16LE(&buf, offset: 18, value: leftStickY)
        writeInt16LE(&buf, offset: 20, value: rightStickX)
        writeInt16LE(&buf, offset: 22, value: rightStickY)
        // buf[24–25]: reserved (zero)
        buf[26] = 0x55  // magic constant required by GFN protocol
        // buf[27–29]: reserved (zero)
        writeTimestampLE(&buf, offset: 30)                                 // u64 LE microseconds
        return protocolVersion >= 3
            ? wrapGamepadPartiallyReliable(buf, gamepadIndex: controllerId)
            : buf
    }

    // MARK: Keyboard
    // Packet (18 bytes): [UInt32 LE type][UInt16 BE vk][UInt16 BE mods][UInt16 BE scan][UInt64 BE ts]

    func encodeKeyboard(down: Bool, vk: UInt16, scancode: UInt16, modifiers: UInt16) -> Data {
        var buf = Data(count: GFNInput.keyboardPacketSize)
        writeUInt32LE(&buf, offset: 0, value: down ? UInt32(GFNInput.keyDown) : UInt32(GFNInput.keyUp))
        writeUInt16BE(&buf, offset: 4, value: vk)
        writeUInt16BE(&buf, offset: 6, value: modifiers)
        writeUInt16BE(&buf, offset: 8, value: scancode)
        writeTimestampBE(&buf, offset: 10)
        return wrapSingleEvent(buf)
    }

    // MARK: Mouse Move
    // Packet (22 bytes): [UInt32 LE type][Int16 BE dx][Int16 BE dy][6B reserved][UInt64 BE ts]

    func encodeMouseMove(dx: Int16, dy: Int16) -> Data {
        var buf = Data(count: GFNInput.mouseMovePacketSize)
        writeUInt32LE(&buf, offset: 0, value: UInt32(GFNInput.mouseRel))
        writeInt16BE(&buf, offset: 4, value: dx)
        writeInt16BE(&buf, offset: 6, value: dy)
        // bytes 8–13: reserved zeros (already zero from Data init)
        writeTimestampBE(&buf, offset: 14)
        return wrapMouseMoveEvent(buf)
    }

    // MARK: Mouse Button
    // Packet (18 bytes): [UInt32 LE type][UInt8 button][1B pad][4B reserved][UInt64 BE ts]

    func encodeMouseButton(down: Bool, button: UInt8) -> Data {
        var buf = Data(count: GFNInput.mouseButtonPacketSize)
        writeUInt32LE(&buf, offset: 0, value: down ? UInt32(GFNInput.mouseBtnDown) : UInt32(GFNInput.mouseBtnUp))
        buf[4] = button
        // buf[5]: padding; buf[6–9]: reserved — all zero
        writeTimestampBE(&buf, offset: 10)
        return wrapSingleEvent(buf)
    }

    // MARK: Mouse Wheel
    // Packet (22 bytes): [UInt32 LE type][2B reserved][Int16 BE vert][6B reserved][UInt64 BE ts]

    func encodeMouseWheel(delta: Int16) -> Data {
        var buf = Data(count: GFNInput.mouseWheelPacketSize)
        writeUInt32LE(&buf, offset: 0, value: UInt32(GFNInput.mouseWheel))
        // bytes 4–5: horizontal delta = 0
        writeInt16BE(&buf, offset: 6, value: delta)
        // bytes 8–13: reserved; timestamp at 14
        writeTimestampBE(&buf, offset: 14)
        return wrapSingleEvent(buf)
    }

    // MARK: Private Wrappers (Protocol v3)

    /// v3: [0x23][8B ts BE][0x22][payload]  — keyboard, mouse button, mouse wheel
    private func wrapSingleEvent(_ payload: Data) -> Data {
        guard protocolVersion >= 3 else { return payload }
        var buf = Data(count: 10 + payload.count)
        buf[0] = 0x23
        writeTimestampBE(&buf, offset: 1)
        buf[9] = 0x22
        buf.replaceSubrange(10..., with: payload)
        return buf
    }

    /// v3: [0x23][8B ts BE][0x21][2B len BE][payload]  — mouse move (coalesced path)
    private func wrapMouseMoveEvent(_ payload: Data) -> Data {
        guard protocolVersion >= 3 else { return payload }
        var buf = Data(count: 12 + payload.count)
        buf[0] = 0x23
        writeTimestampBE(&buf, offset: 1)
        buf[9] = 0x21
        let len = UInt16(payload.count)
        buf[10] = UInt8(len >> 8)
        buf[11] = UInt8(len & 0xFF)
        buf.replaceSubrange(12..., with: payload)
        return buf
    }

    private func wrapGamepadPartiallyReliable(_ payload: Data, gamepadIndex: Int) -> Data {
        let seq = nextGamepadSequence(gamepadIndex)
        // [0x23][8B ts][0x26][1B idx][2B seq BE][0x21][2B size BE][payload]
        var buf = Data(count: 9 + 1 + 1 + 2 + 1 + 2 + payload.count)
        buf[0] = 0x23
        writeTimestampBE(&buf, offset: 1)
        buf[9]  = 0x26
        buf[10] = UInt8(gamepadIndex & 0xFF)
        buf[11] = UInt8(seq >> 8)
        buf[12] = UInt8(seq & 0xFF)
        buf[13] = 0x21
        buf[14] = UInt8(payload.count >> 8)
        buf[15] = UInt8(payload.count & 0xFF)
        buf.replaceSubrange(16..., with: payload)
        return buf
    }

    private func nextGamepadSequence(_ idx: Int) -> UInt16 {
        let current = gamepadSequence[idx] ?? 1
        gamepadSequence[idx] = current &+ 1  // wraps at 65535
        return current
    }

    // MARK: Write Helpers

    private func writeUInt16LE(_ buf: inout Data, offset: Int, value: UInt16) {
        buf[offset]     = UInt8(value & 0xFF)
        buf[offset + 1] = UInt8(value >> 8)
    }

    private func writeTimestampLE(_ buf: inout Data, offset: Int) {
        let tsUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        buf[offset]     = UInt8(tsUs        & 0xFF)
        buf[offset + 1] = UInt8((tsUs >> 8)  & 0xFF)
        buf[offset + 2] = UInt8((tsUs >> 16) & 0xFF)
        buf[offset + 3] = UInt8((tsUs >> 24) & 0xFF)
        buf[offset + 4] = UInt8((tsUs >> 32) & 0xFF)
        buf[offset + 5] = UInt8((tsUs >> 40) & 0xFF)
        buf[offset + 6] = UInt8((tsUs >> 48) & 0xFF)
        buf[offset + 7] = UInt8((tsUs >> 56) & 0xFF)
    }

    private func writeUInt32LE(_ buf: inout Data, offset: Int, value: UInt32) {
        buf[offset]     = UInt8(value & 0xFF)
        buf[offset + 1] = UInt8((value >> 8) & 0xFF)
        buf[offset + 2] = UInt8((value >> 16) & 0xFF)
        buf[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeUInt16BE(_ buf: inout Data, offset: Int, value: UInt16) {
        buf[offset]     = UInt8(value >> 8)
        buf[offset + 1] = UInt8(value & 0xFF)
    }

    private func writeInt16BE(_ buf: inout Data, offset: Int, value: Int16) {
        let v = UInt16(bitPattern: value)
        buf[offset]     = UInt8(v >> 8)
        buf[offset + 1] = UInt8(v & 0xFF)
    }

    private func writeInt16LE(_ buf: inout Data, offset: Int, value: Int16) {
        let v = UInt16(bitPattern: value)
        buf[offset]     = UInt8(v & 0xFF)
        buf[offset + 1] = UInt8(v >> 8)
    }

    private func writeTimestampBE(_ buf: inout Data, offset: Int) {
        let tsUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        buf[offset]     = UInt8((tsUs >> 56) & 0xFF)
        buf[offset + 1] = UInt8((tsUs >> 48) & 0xFF)
        buf[offset + 2] = UInt8((tsUs >> 40) & 0xFF)
        buf[offset + 3] = UInt8((tsUs >> 32) & 0xFF)
        buf[offset + 4] = UInt8((tsUs >> 24) & 0xFF)
        buf[offset + 5] = UInt8((tsUs >> 16) & 0xFF)
        buf[offset + 6] = UInt8((tsUs >>  8) & 0xFF)
        buf[offset + 7] = UInt8((tsUs      ) & 0xFF)
    }
}

// MARK: - GCController → XInput Mapping

func mapGCControllerToXInput(_ controller: GCController, deadzone: Float = 0.15) -> (
    buttons: UInt16, leftTrigger: UInt8, rightTrigger: UInt8,
    lx: Int16, ly: Int16, rx: Int16, ry: Int16
) {
    guard let pad = controller.extendedGamepad else {
        return (0, 0, 0, 0, 0, 0, 0)
    }

    var buttons: UInt16 = 0
    func pressed(_ e: GCControllerButtonInput) -> Bool { e.isPressed }

    if pressed(pad.dpad.up)    { buttons |= GFNInput.dpadUp }
    if pressed(pad.dpad.down)  { buttons |= GFNInput.dpadDown }
    if pressed(pad.dpad.left)  { buttons |= GFNInput.dpadLeft }
    if pressed(pad.dpad.right) { buttons |= GFNInput.dpadRight }
    if pressed(pad.buttonMenu) { buttons |= GFNInput.start }
    var backPressed = pressed(pad.buttonOptions ?? pad.buttonMenu)
    if let dualSense = pad as? GCDualSenseGamepad, dualSense.touchpadButton.isPressed {
        backPressed = true
    } else if let dualShock = pad as? GCDualShockGamepad, dualShock.touchpadButton.isPressed {
        backPressed = true
    }
    if backPressed { buttons |= GFNInput.back }

    if let home = pad.buttonHome, pressed(home) {
        buttons |= GFNInput.guide
    }
    if let ls = pad.leftThumbstickButton,  pressed(ls) { buttons |= GFNInput.ls }
    if let rs = pad.rightThumbstickButton, pressed(rs) { buttons |= GFNInput.rs }
    if pressed(pad.leftShoulder)  { buttons |= GFNInput.lb }
    if pressed(pad.rightShoulder) { buttons |= GFNInput.rb }
    if pressed(pad.buttonA) { buttons |= GFNInput.buttonA }
    if pressed(pad.buttonB) { buttons |= GFNInput.buttonB }
    if pressed(pad.buttonX) { buttons |= GFNInput.buttonX }
    if pressed(pad.buttonY) { buttons |= GFNInput.buttonY }

    let lt = UInt8(clamping: Int(pad.leftTrigger.value * 255))
    let rt = UInt8(clamping: Int(pad.rightTrigger.value * 255))

    let lx = normalizeAxis(pad.leftThumbstick.xAxis.value, deadzone: deadzone)
    let ly = normalizeAxis(pad.leftThumbstick.yAxis.value, deadzone: deadzone)
    let rx = normalizeAxis(pad.rightThumbstick.xAxis.value, deadzone: deadzone)
    let ry = normalizeAxis(pad.rightThumbstick.yAxis.value, deadzone: deadzone)

    return (buttons, lt, rt, lx, ly, rx, ry)
}

private func normalizeAxis(_ v: Float, deadzone: Float) -> Int16 {
    let clamped = max(-1.0, min(1.0, v))
    if abs(clamped) < deadzone { return 0 }
    return Int16(clamped < 0 ? clamped * 32768 : clamped * 32767)
}

// MARK: - DataChannelSender

/// Abstracts the WebRTC data channel so the WebRTC dependency stays in GFNStreamController.
protocol DataChannelSender: AnyObject {
    func sendData(_ data: Data)
}

// MARK: - InputSender

/// Monitors connected GCControllers and keyboard/mouse events; sends encoded input
/// over a WebRTC data channel at 60 Hz.
final class InputSender {
    /// Pixel delta applied per unit of Siri Remote axis deflection per 60 Hz frame.
    /// Tune this if the cursor feels too fast or too slow.
    static let remoteSensitivity: Float = 250.0

    /// Sensitivity scale for the PlayStation controller touchpad.
    static let playStationTouchpadSensitivity: Float = 750.0

    /// Siri Remote input mode. Defaults to .mouse so the touchpad drives the cursor.
    var remoteMode: RemoteInputMode = .mouse

    /// Radial deadzone for analog stick axes (0.0–1.0). Set from StreamSettings.controllerDeadzone.
    var deadzone: Float = 0.15

    /// Whether vibration/rumble is enabled for controllers. Set from StreamSettings.vibrationEnabled.
    var vibrationEnabled: Bool = true

    /// When true, Siri Remote and keyboard/mouse input is suppressed (e.g. while the HUD is visible).
    var isPaused = false

    /// Called when the user long-presses the overlay trigger button to toggle the GFN overlay.
    var menuToggleHandler: (() -> Void)?

    /// Called when the user presses Left Shoulder + Right Shoulder to toggle stats HUD.
    var statsToggleHandler: (() -> Void)?

    /// Which controller button triggers the overlay on long-press. Matches StreamSettings.overlayTriggerButton.
    var overlayTriggerButton: OverlayTriggerButton = .start

    /// Called when remoteMode changes due to controller connect/disconnect auto-switching.
    var onRemoteModeChanged: ((RemoteInputMode) -> Void)?

    private weak var channel: DataChannelSender?
    let encoder = InputEncoder()
    private var sendTimer: Timer?
    private var heartbeatTimer: Timer?
    private var observations: [NSObjectProtocol] = []

    // Gamepad bitmap: bit i = extended gamepad i is connected (matches official GFN protocol)
    private var gamepadBitmap: UInt16 = 0

    // Siri Remote state tracking
    private var lastMicroDpad: (x: Float, y: Float) = (0, 0)
    private var lastMicroButtonA = false

    // DualSense touchpad state tracking
    private var lastDualSenseTouchpad: (x: Float, y: Float) = (0, 0)
    private var lastDualSenseTouchpadClick = false
    private var smoothedTouchpadDx: Float = 0.0
    private var smoothedTouchpadDy: Float = 0.0

    // Per-controller overlay trigger hold duration (ticks at 60 Hz)
    private var overlayHoldTicks: [Int: Int] = [:]
    // 1800 ms at 60 Hz, matches official GFN IGO gamepadLongStartPressDefaultDuration
    private static let overlayLongPressThreshold = 108

    // Cache haptic engines per controller and locality
    private var hapticEngines = [String: CHHapticEngine]()

    init(channel: DataChannelSender) {
        self.channel = channel
    }

    // MARK: Start / Stop

    func start() {
        registerControllerNotifications()
        // 60 Hz for responsive mouse and gamepad input.
        sendTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Heartbeat every 2 s — keeps the server's virtual gamepad alive between real inputs.
        // Sent unconditionally (not gated on isPaused) to maintain the connection.
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.channel?.sendData(self.encoder.encodeHeartbeat())
        }
        // Advertise haptics support to GFN server
        updateHapticsAdvertisement()
    }

    func stop() {
        sendTimer?.invalidate()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        hapticEngines.removeAll()
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        observations.removeAll()
    }

    func setProtocolVersion(_ v: Int) {
        encoder.setProtocolVersion(v)
    }

    // MARK: Remote Mode

    func toggleRemoteMode() {
        switch remoteMode {
        case .mouse:     remoteMode = .gamepad
        case .gamepad:   remoteMode = .dualsense
        case .dualsense: remoteMode = .mouse
        }
        applyRemoteMode()
    }

    private func applyRemoteMode() {
        lastMicroDpad = (0, 0)
        lastMicroButtonA = false
        lastDualSenseTouchpad = (0, 0)
        lastDualSenseTouchpadClick = false
        smoothedTouchpadDx = 0.0
        smoothedTouchpadDy = 0.0
        overlayHoldTicks.removeAll()
        for controller in GCController.controllers() where controller.extendedGamepad != nil {
            if remoteMode == .gamepad || remoteMode == .dualsense {
                claimControllerInput(controller)
            } else {
                releaseControllerInput(controller)
            }
        }
    }

    // MARK: Private — Tick

    private func tick() {
        let controllers = GCController.controllers()
        let extended = controllers.filter { $0.extendedGamepad != nil }
        let micro    = controllers.filter { $0.extendedGamepad == nil && $0.microGamepad != nil }

        if extended.isEmpty && micro.isEmpty { return }

        // PlayStation touchpads: poll touchpad for mouse movement alongside regular gamepad packets
        if !isPaused {
            if let psController = extended.first(where: { $0.extendedGamepad is GCDualSenseGamepad || $0.extendedGamepad is GCDualShockGamepad }) {
                handlePlayStationTouchpad(psController)
            }
        }

        if remoteMode == .gamepad || remoteMode == .dualsense {
            // Gamepad/DualSense mode: extended controller owns the game; remote is suppressed when
            // a real controller is present (otherwise the remote's empty state overwrites it).
            for (idx, controller) in extended.prefix(4).enumerated() {
                sendExtendedGamepad(controller, controllerId: idx, allowOverlayTrigger: true)
            }

            // Only use the Siri Remote as a gamepad when no real controller is connected
            if extended.isEmpty, !isPaused, let remote = micro.first {
                handleMicroGamepad(remote)
            }
        } else {
            // Mouse mode keeps the Siri Remote as a cursor, but a connected game controller
            // must still be reported to GFN so games do not fall back to keyboard/mouse input.
            overlayHoldTicks.removeAll()
            for (idx, controller) in extended.prefix(4).enumerated() {
                sendExtendedGamepad(controller, controllerId: idx, allowOverlayTrigger: false)
            }
            if !isPaused, let remote = micro.first {
                handleMicroGamepad(remote)
            }
        }
    }

    private func sendExtendedGamepad(_ controller: GCController, controllerId idx: Int, allowOverlayTrigger: Bool) {
        var (btns, lt, rt, lx, ly, rx, ry) = mapGCControllerToXInput(controller, deadzone: deadzone)

        if let pad = controller.extendedGamepad {
            // ── Combo: LB + RB pressed simultaneously ──
            let lbDown = pad.leftShoulder.isPressed
            let rbDown = pad.rightShoulder.isPressed
            let statsComboKey = idx + 100
            if lbDown && rbDown {
                let ticks = overlayHoldTicks[statsComboKey] ?? 0
                if ticks == -1 {
                    // Already fired, wait for release
                } else {
                    let newTicks = ticks + 1
                    overlayHoldTicks[statsComboKey] = newTicks
                    if newTicks == Self.overlayLongPressThreshold {
                        menuToggleHandler?()
                        overlayHoldTicks[statsComboKey] = -1
                    }
                }
                btns &= ~GFNInput.lb
                btns &= ~GFNInput.rb
            } else {
                let ticks = overlayHoldTicks[statsComboKey] ?? 0
                if ticks > 0 && ticks < Self.overlayLongPressThreshold {
                    statsToggleHandler?()
                }
                overlayHoldTicks[statsComboKey] = 0
            }

            if allowOverlayTrigger {
                let menuDown   = pad.buttonMenu.isPressed
                let viewDown   = pad.buttonOptions?.isPressed ?? false

                // ── Combo: Menu + View pressed simultaneously → instant overlay toggle ──
                // Uses a per-controller flag so the handler only fires once per press,
                // not every tick while both buttons are held.
                let comboKey = -(idx + 1)  // negative index to avoid clash with long-press keys
                if menuDown && viewDown {
                    let alreadyFired = (overlayHoldTicks[comboKey] ?? 0) != 0
                    if !alreadyFired {
                        overlayHoldTicks[comboKey] = 1
                        // Suppress both buttons from the GFN packet
                        btns &= ~GFNInput.start
                        btns &= ~GFNInput.back
                        // Reset long-press counter so it doesn't also fire
                        overlayHoldTicks[idx] = 0
                        menuToggleHandler?()
                    } else {
                        // Still suppress the buttons while the combo is held
                        btns &= ~GFNInput.start
                        btns &= ~GFNInput.back
                    }
                } else {
                    // Combo released — clear the one-shot flag
                    overlayHoldTicks[comboKey] = 0

                    // ── Single-button long-press overlay trigger (existing behaviour) ──
                    let held: Bool
                    switch overlayTriggerButton {
                    case .start:   held = menuDown
                    case .options: held = viewDown
                    }
                    if held {
                        let ticks = (overlayHoldTicks[idx] ?? 0) + 1
                        overlayHoldTicks[idx] = ticks
                        if ticks == Self.overlayLongPressThreshold {
                            switch overlayTriggerButton {
                            case .start:   btns &= ~GFNInput.start
                            case .options: btns &= ~GFNInput.back
                            }
                            menuToggleHandler?()
                        }
                    } else {
                        overlayHoldTicks[idx] = 0
                    }
                }
            }
        }

        let data = encoder.encodeGamepad(
            controllerId: idx,
            buttons: btns,
            leftTrigger: lt,
            rightTrigger: rt,
            leftStickX: lx,
            leftStickY: ly,
            rightStickX: rx,
            rightStickY: ry,
            gamepadBitmap: gamepadBitmap
        )
        channel?.sendData(data)
    }

    private func handleMicroGamepad(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }

        let curX = pad.dpad.xAxis.value
        let curY = pad.dpad.yAxis.value
        // Treat the touchpad as "not being touched" when position is near centre.
        // This prevents a snap-back mouseRel when the finger lifts and dpad returns to (0,0).
        let isTouching  = abs(curX) > 0.02 || abs(curY) > 0.02
        let wasTouching = abs(lastMicroDpad.x) > 0.02 || abs(lastMicroDpad.y) > 0.02
        // Compute delta before updating the reference so we don't compare a value with itself.
        let dx = curX - lastMicroDpad.x
        let dy = curY - lastMicroDpad.y
        lastMicroDpad = (curX, curY)

        switch remoteMode {
        case .mouse:
            // Only send delta while the finger is continuously on the pad.
            // Ignore the first frame of a new touch (wasTouching=false) and the
            // release frame (isTouching=false) to avoid jump artefacts.
            if isTouching && wasTouching && (abs(dx) > 0.0005 || abs(dy) > 0.0005) {
                let pxDx = Int16(clamping: Int((dx * Self.remoteSensitivity).rounded()))
                let pxDy = Int16(clamping: Int((-dy * Self.remoteSensitivity).rounded()))
                sendMouseMove(dx: pxDx, dy: pxDy)
            }

            // Select / click → left mouse button
            let aPressed = pad.buttonA.isPressed
            if aPressed != lastMicroButtonA {
                lastMicroButtonA = aPressed
                sendMouseButton(down: aPressed, button: 1)
            }

            // Play/Pause is handled by VideoSurfaceView (UIKit pressesBegan) as an overlay toggle.
            // Do not forward it to the game from here to avoid double-firing.
            _ = pad.buttonX.isPressed  // read to prevent GameController from coalescing

        case .gamepad:
            var buttons: UInt16 = 0
            if pad.dpad.up.isPressed    { buttons |= GFNInput.dpadUp }
            if pad.dpad.down.isPressed  { buttons |= GFNInput.dpadDown }
            if pad.dpad.left.isPressed  { buttons |= GFNInput.dpadLeft }
            if pad.dpad.right.isPressed { buttons |= GFNInput.dpadRight }
            if pad.buttonA.isPressed    { buttons |= GFNInput.buttonA }
            // buttonX (Play/Pause) is reserved for the overlay toggle — not forwarded to game

            let data = encoder.encodeGamepad(
                controllerId: 0, buttons: buttons,
                leftTrigger: 0, rightTrigger: 0,
                leftStickX: 0, leftStickY: 0,
                rightStickX: 0, rightStickY: 0,
                gamepadBitmap: gamepadBitmap | 1  // Siri Remote acts as slot 0
            )
            channel?.sendData(data)

        case .dualsense:
            break  // Siri Remote is suppressed in DualSense mode; touchpad handled separately
        }
    }

    private func handlePlayStationTouchpad(_ controller: GCController) {
        let touchpadPrimary: GCControllerDirectionPad
        let touchpadButton: GCControllerButtonInput

        if let ds = controller.extendedGamepad as? GCDualSenseGamepad {
            touchpadPrimary = ds.touchpadPrimary
            touchpadButton = ds.touchpadButton
        } else if let ds4 = controller.extendedGamepad as? GCDualShockGamepad {
            touchpadPrimary = ds4.touchpadPrimary
            touchpadButton = ds4.touchpadButton
        } else {
            return
        }

        let curX = touchpadPrimary.xAxis.value
        let curY = touchpadPrimary.yAxis.value

        let isTouching  = abs(curX) > 0.02 || abs(curY) > 0.02
        let wasTouching = abs(lastDualSenseTouchpad.x) > 0.02 || abs(lastDualSenseTouchpad.y) > 0.02
        let dx = curX - lastDualSenseTouchpad.x
        let dy = curY - lastDualSenseTouchpad.y
        lastDualSenseTouchpad = (curX, curY)

        let alpha: Float = 0.25
        if isTouching && wasTouching {
            if abs(dx) > 0.0005 || abs(dy) > 0.0005 {
                smoothedTouchpadDx = (smoothedTouchpadDx * (1.0 - alpha)) + (dx * alpha)
                smoothedTouchpadDy = (smoothedTouchpadDy * (1.0 - alpha)) + (dy * alpha)
            } else {
                smoothedTouchpadDx *= 0.5
                smoothedTouchpadDy *= 0.5
            }
            let pxDx = Int16(clamping: Int((smoothedTouchpadDx * Self.playStationTouchpadSensitivity).rounded()))
            let pxDy = Int16(clamping: Int((-smoothedTouchpadDy * Self.playStationTouchpadSensitivity).rounded()))
            if pxDx != 0 || pxDy != 0 {
                sendMouseMove(dx: pxDx, dy: pxDy)
            }
        } else {
            smoothedTouchpadDx = 0.0
            smoothedTouchpadDy = 0.0
        }

        let clicked = touchpadButton.isPressed
        if clicked != lastDualSenseTouchpadClick {
            lastDualSenseTouchpadClick = clicked
            sendMouseButton(down: clicked, button: 1)
        }
    }

    // MARK: Private — Controller Notifications

    private func registerControllerNotifications() {
        let connectObs = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] notif in
            if let c = notif.object as? GCController {
                self?.controllerConnected(c)
            }
        }
        let disconnectObs = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] notif in
            if let c = notif.object as? GCController {
                self?.controllerDisconnected(c)
            }
        }
        // GCMouse: Bluetooth mice on tvOS 14+ (raw deltas — no system cursor acceleration)
        let mouseConnectObs = NotificationCenter.default.addObserver(
            forName: .GCMouseDidConnect, object: nil, queue: .main
        ) { [weak self] notif in
            if let mouse = notif.object as? GCMouse {
                self?.setupMouseHandlers(for: mouse)
            }
        }
        let mouseDisconnectObs = NotificationCenter.default.addObserver(
            forName: .GCMouseDidDisconnect, object: nil, queue: .main
        ) { [weak self] notif in
            if let mouse = notif.object as? GCMouse {
                self?.clearMouseHandlers(for: mouse)
            }
        }
        observations = [connectObs, disconnectObs, mouseConnectObs, mouseDisconnectObs]
        GCController.startWirelessControllerDiscovery()

        // Seed gamepadBitmap for controllers already connected before InputSender started.
        // System gesture ownership is only claimed when in gamepad mode (starts as .mouse).
        for controller in GCController.controllers() where controller.extendedGamepad != nil {
            if remoteMode == .gamepad { claimControllerInput(controller) }
            let idx = GCController.controllers().firstIndex(where: { $0 === controller }) ?? 0
            let connectedBit = UInt16(1 << (idx & 3))
            let xboxBit = UInt16(1 << ((idx & 3) + 8))
            gamepadBitmap |= connectedBit
            gamepadBitmap |= xboxBit
        }

        // Wire up any mice already connected at start time
        for mouse in GCMouse.mice() {
            setupMouseHandlers(for: mouse)
        }
    }

    private func setupMouseHandlers(for mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }

        // Raw hardware delta movement → mouseRel packets
        // Negate Y: hardware "move up" = positive deltaY → screen up = negative dy.
        input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            guard let self, !self.isPaused else { return }
            let dx = Int16(clamping: Int(deltaX.rounded()))
            let dy = Int16(clamping: Int((-deltaY).rounded()))
            if dx != 0 || dy != 0 {
                self.sendMouseMove(dx: dx, dy: dy)
            }
        }

        // Left / right / middle buttons
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendMouseButton(down: pressed, button: 1)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendMouseButton(down: pressed, button: 3)
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.sendMouseButton(down: pressed, button: 2)
        }

        // Scroll wheel — vertical axis only, scale factor of 3 for comfortable feel
        input.scroll.valueChangedHandler = { [weak self] _, _, yValue in
            guard let self, !self.isPaused else { return }
            let delta = Int16(clamping: Int((-yValue * 3).rounded()))
            if delta != 0 { self.sendMouseWheel(delta: delta) }
        }
    }

    private func clearMouseHandlers(for mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = nil
        input.leftButton.pressedChangedHandler = nil
        input.rightButton?.pressedChangedHandler = nil
        input.middleButton?.pressedChangedHandler = nil
        input.scroll.valueChangedHandler = nil
    }

    private func claimControllerInput(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        // Prevent tvOS from intercepting any face/shoulder button as system navigation
        // (O/Circle and B are mapped to "back" by the OS by default)
        let buttons: [GCControllerButtonInput?] = [
            pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
            pad.buttonMenu, pad.buttonOptions,
            pad.leftShoulder, pad.rightShoulder,
            pad.leftTrigger, pad.rightTrigger,
            pad.leftThumbstickButton, pad.rightThumbstickButton,
        ]
        for btn in buttons.compactMap({ $0 }) {
            btn.preferredSystemGestureState = .disabled
        }
    }

    private func releaseControllerInput(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let buttons: [GCControllerButtonInput?] = [
            pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
            pad.buttonMenu, pad.buttonOptions,
            pad.leftShoulder, pad.rightShoulder,
            pad.leftTrigger, pad.rightTrigger,
            pad.leftThumbstickButton, pad.rightThumbstickButton,
        ]
        for btn in buttons.compactMap({ $0 }) {
            btn.preferredSystemGestureState = .enabled
        }
    }

    private func controllerConnected(_ controller: GCController) {
        guard controller.extendedGamepad != nil else { return }
        let idx = GCController.controllers().firstIndex(where: { $0 === controller }) ?? 0
        let connectedBit = UInt16(1 << (idx & 3))
        let xboxBit = UInt16(1 << ((idx & 3) + 8))
        gamepadBitmap |= connectedBit
        gamepadBitmap |= xboxBit // Advertise Xbox compatibility/vibration support
        
        // Auto-switch to gamepad mode when a real controller connects.
        if remoteMode == .mouse {
            remoteMode = .gamepad
            applyRemoteMode()
            onRemoteModeChanged?(remoteMode)
        } else {
            claimControllerInput(controller)
        }
        let data = encoder.encodeGamepad(
            controllerId: idx, buttons: 0, leftTrigger: 0, rightTrigger: 0,
            leftStickX: 0, leftStickY: 0, rightStickX: 0, rightStickY: 0,
            gamepadBitmap: gamepadBitmap
        )
        channel?.sendData(data)
        updateHapticsAdvertisement()
    }

    private func controllerDisconnected(_ controller: GCController) {
        guard controller.extendedGamepad != nil else { return }
        let idx = GCController.controllers().firstIndex(where: { $0 === controller }) ?? 0
        let connectedBit = UInt16(1 << (idx & 3))
        let xboxBit = UInt16(1 << ((idx & 3) + 8))
        gamepadBitmap &= ~connectedBit
        gamepadBitmap &= ~xboxBit
        
        // Revert to mouse mode when the last controller disconnects.
        if (gamepadBitmap & 0xFF) == 0 && remoteMode != .mouse {
            remoteMode = .mouse
            applyRemoteMode()
            onRemoteModeChanged?(remoteMode)
        }
        let data = encoder.encodeGamepad(
            controllerId: idx, buttons: 0, leftTrigger: 0, rightTrigger: 0,
            leftStickX: 0, leftStickY: 0, rightStickX: 0, rightStickY: 0,
            gamepadBitmap: gamepadBitmap
        )
        channel?.sendData(data)
        updateHapticsAdvertisement()
    }

    // MARK: - GFN Haptics Advertisement

    func updateHapticsAdvertisement() {
        let hasHapticGamepad = !GCController.controllers().filter { $0.extendedGamepad != nil && $0.haptics != nil }.isEmpty
        let data = encoder.encodeHapticsEnabled(hasHapticGamepad)
        channel?.sendData(data)
        print("[Haptics] Sent haptics advertisement: \(hasHapticGamepad)")
    }

    // MARK: - Incoming Messages & Haptics Parsing

    /// Entry point for all incoming messages on GFN input channels during active streaming.
    func handleIncomingMessage(_ bytes: Data) {
        guard vibrationEnabled else { return }
        guard bytes.count >= 2 else { return }

        // If it is wrapped in v3 envelope (starts with 0x23 / 35)
        if bytes[0] == 0x23 {
            guard bytes.count >= 10 else { return }
            // Unwrap the v3 envelope: payload starts at index 9 (which is 0x22 or other sub-message wrapper)
            let unwrapped = bytes.subdata(in: 9..<bytes.count)
            parseUnwrappedMessage(unwrapped)
            return
        }

        parseUnwrappedMessage(bytes)
    }

    private func parseUnwrappedMessage(_ data: Data) {
        guard data.count >= 2 else { return }

        let firstWord = data.getUInt16LE(at: 0)
        if firstWord == 267 { // 0x010B = Legacy Haptic packet
            parseLegacyHapticPacket(data, offset: 2)
            return
        }

        let wrapperType = data[0]
        switch wrapperType {
        case 34: // 0x22 = GFN sub-message wrapper
            parseInputSubMessage(data, offset: 1)
        case 32, 33, 35, 36, 255:
            // Ignore other wrapper types (e.g. keyboard echo, mouse echo, etc.)
            break
        default:
            // Fallback: try parsing as legacy haptic from offset 0
            parseLegacyHapticPacket(data, offset: 0)
        }
    }

    private func parseInputSubMessage(_ data: Data, offset: Int) {
        guard offset + 4 <= data.count else { return }
        let type = data.getUInt32LE(at: offset)
        if type == 267 {
            parseLegacyHapticPacket(data, offset: offset + 4)
        } else if type == 17 { // 0x11 = Oc Haptic packet
            parseOcHapticPacket(data, offset: offset + 4)
        } else {
            print("[Haptics] Unknown sub-message type \(type)")
        }
    }

    private func parseLegacyHapticPacket(_ data: Data, offset: Int) {
        guard offset + 10 <= data.count else {
            print("[Haptics] Malformed legacy haptic packet (offset: \(offset), size: \(data.count))")
            return
        }

        let kind = data.getUInt16LE(at: offset)
        if kind != 1 {
            // kind == 0 is sometimes sent as a heartbeat/ping, no need to warn
            return
        }

        let length = data.getUInt16LE(at: offset + 2)
        if length < 6 { return }

        let controllerId = Int(data.getUInt16LE(at: offset + 4))
        let weakMagnitude = data.getUInt16LE(at: offset + 6)
        let strongMagnitude = data.getUInt16LE(at: offset + 8)

        let weak = Float(weakMagnitude) / 65535.0
        let strong = Float(strongMagnitude) / 65535.0

        triggerGamepadRumble(controllerId: controllerId, weak: weak, strong: strong)
    }

    private func parseOcHapticPacket(_ data: Data, offset: Int) {
        guard offset + 9 <= data.count else {
            print("[Haptics] Malformed Oc haptic packet (offset: \(offset), size: \(data.count))")
            return
        }

        let controllerByte = data[offset]
        if controllerByte < 6 || controllerByte >= 10 {
            print("[Haptics] Unknown Oc controller byte: \(controllerByte)")
            return
        }

        let reportKind = data[offset + 3]
        let flags = data[offset + 4]
        if reportKind != 5 || (flags & ~1) != 0 {
            print("[Haptics] Unsupported Oc report kind=\(reportKind) flags=0x\(String(format: "%02X", flags))")
            return
        }

        let controllerId = Int(controllerByte - 6)
        let weakMagnitude = UInt16(data[offset + 7]) << 8
        let strongMagnitude = UInt16(data[offset + 8]) << 8

        let weak = Float(weakMagnitude) / 65535.0
        let strong = Float(strongMagnitude) / 65535.0

        triggerGamepadRumble(controllerId: controllerId, weak: weak, strong: strong)
    }

    private var lastRumblePlayTime = [Int: Date]()

    private func triggerGamepadRumble(controllerId: Int, weak: Float, strong: Float) {
        let isStop = weak <= 0.01 && strong <= 0.01
        let now = Date()

        let controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        guard !controllers.isEmpty else { return }

        // Match controller by controllerId, or fall back to the first one
        let targetController = controllerId < controllers.count ? controllers[controllerId] : controllers[0]

        guard let haptics = targetController.haptics else { return }
        let supported = haptics.supportedLocalities

        if isStop {
            // Stop rumble immediately
            for locality in supported {
                let key = "\(ObjectIdentifier(targetController).hashValue)-\(locality.rawValue)"
                if let engine = hapticEngines[key] {
                    try? engine.stop()
                }
            }
            lastRumblePlayTime.removeValue(forKey: controllerId)
            return
        }

        // Throttle active rumble requests to once every 150ms per controller
        if let lastPlay = lastRumblePlayTime[controllerId], now.timeIntervalSince(lastPlay) < 0.15 {
            return
        }
        lastRumblePlayTime[controllerId] = now

        let durationSec: TimeInterval = 0.20 // 200ms duration to bridge throttled updates smoothly

        func play(locality: GCHapticsLocality, intensity: Float) -> Bool {
            guard intensity > 0.01 else { return false }
            guard supported.contains(locality) else { return false }

            // Apply square-root curve to lift faint values (logarithmic perception)
            // and enforce a solid baseline of 0.35 to overcome physical motor inertia.
            let adjustedIntensity = min(1.0, max(0.35, sqrt(intensity)))
            let adjustedSharpness = min(1.0, max(0.6, sqrt(intensity)))

            let key = "\(ObjectIdentifier(targetController).hashValue)-\(locality.rawValue)"
            let engine: CHHapticEngine
            if let existing = hapticEngines[key] {
                engine = existing
            } else if let created = haptics.createEngine(withLocality: locality) {
                engine = created
                hapticEngines[key] = created
            } else {
                return false
            }

            do {
                try engine.start()
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: adjustedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: adjustedSharpness)
                    ],
                    relativeTime: 0,
                    duration: durationSec
                )
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return true
            } catch {
                print("[Haptics] Failed to play on \(locality.rawValue): \(error)")
                return false
            }
        }

        // Map strong magnitude to leftHandle, weak magnitude to rightHandle
        let playedAny = [
            play(locality: .leftHandle, intensity: strong),
            play(locality: .rightHandle, intensity: weak)
        ].contains(true)

        // Fallback for controllers that only support .default
        if !playedAny {
            let maxIntensity = max(weak, strong)
            if maxIntensity > 0.01 {
                _ = play(locality: .default, intensity: maxIntensity)
            }
        }
    }
}

// MARK: - InputSender: InputEventHandler

extension InputSender: InputEventHandler {
    func sendKeyEvent(down: Bool, vk: UInt16, scancode: UInt16, modifiers: UInt16) {
        guard !isPaused else { return }
        channel?.sendData(encoder.encodeKeyboard(down: down, vk: vk, scancode: scancode, modifiers: modifiers))
    }

    func sendVirtualKeyEvent(down: Bool, vk: UInt16, scancode: UInt16, modifiers: UInt16) {
        channel?.sendData(encoder.encodeKeyboard(down: down, vk: vk, scancode: scancode, modifiers: modifiers))
    }

    func sendMouseMove(dx: Int16, dy: Int16) {
        guard !isPaused else { return }
        channel?.sendData(encoder.encodeMouseMove(dx: dx, dy: dy))
    }

    func sendMouseButton(down: Bool, button: UInt8) {
        guard !isPaused else { return }
        channel?.sendData(encoder.encodeMouseButton(down: down, button: button))
    }

    func sendMouseWheel(delta: Int16) {
        guard !isPaused else { return }
        channel?.sendData(encoder.encodeMouseWheel(delta: delta))
    }
}

// MARK: - Data Helpers

private extension Data {
    func getUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func getUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }
}
