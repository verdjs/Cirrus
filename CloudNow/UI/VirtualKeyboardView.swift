import SwiftUI

struct VirtualKeyInfo {
    let vk: UInt16
    let scancode: UInt16
}

struct VirtualKeyboardView: View {
    let streamController: GFNStreamController
    
    @State private var isShiftActive = false
    
    private let keysInfo: [String: VirtualKeyInfo] = [
        "1": VirtualKeyInfo(vk: 0x31, scancode: 0x02),
        "2": VirtualKeyInfo(vk: 0x32, scancode: 0x03),
        "3": VirtualKeyInfo(vk: 0x33, scancode: 0x04),
        "4": VirtualKeyInfo(vk: 0x34, scancode: 0x05),
        "5": VirtualKeyInfo(vk: 0x35, scancode: 0x06),
        "6": VirtualKeyInfo(vk: 0x36, scancode: 0x07),
        "7": VirtualKeyInfo(vk: 0x37, scancode: 0x08),
        "8": VirtualKeyInfo(vk: 0x38, scancode: 0x09),
        "9": VirtualKeyInfo(vk: 0x39, scancode: 0x0A),
        "0": VirtualKeyInfo(vk: 0x30, scancode: 0x0B),
        "-": VirtualKeyInfo(vk: 0xBD, scancode: 0x0C),
        "=": VirtualKeyInfo(vk: 0xBB, scancode: 0x0D),
        "Backspace": VirtualKeyInfo(vk: 0x08, scancode: 0x0E),

        "q": VirtualKeyInfo(vk: 0x51, scancode: 0x10),
        "w": VirtualKeyInfo(vk: 0x57, scancode: 0x11),
        "e": VirtualKeyInfo(vk: 0x45, scancode: 0x12),
        "r": VirtualKeyInfo(vk: 0x52, scancode: 0x13),
        "t": VirtualKeyInfo(vk: 0x54, scancode: 0x14),
        "y": VirtualKeyInfo(vk: 0x59, scancode: 0x15),
        "u": VirtualKeyInfo(vk: 0x55, scancode: 0x16),
        "i": VirtualKeyInfo(vk: 0x49, scancode: 0x17),
        "o": VirtualKeyInfo(vk: 0x4F, scancode: 0x18),
        "p": VirtualKeyInfo(vk: 0x50, scancode: 0x19),
        "[": VirtualKeyInfo(vk: 0xDB, scancode: 0x1A),
        "]": VirtualKeyInfo(vk: 0xDD, scancode: 0x1B),
        "Enter": VirtualKeyInfo(vk: 0x0D, scancode: 0x1C),

        "a": VirtualKeyInfo(vk: 0x41, scancode: 0x1E),
        "s": VirtualKeyInfo(vk: 0x53, scancode: 0x1F),
        "d": VirtualKeyInfo(vk: 0x44, scancode: 0x20),
        "f": VirtualKeyInfo(vk: 0x46, scancode: 0x21),
        "g": VirtualKeyInfo(vk: 0x47, scancode: 0x22),
        "h": VirtualKeyInfo(vk: 0x48, scancode: 0x23),
        "j": VirtualKeyInfo(vk: 0x4A, scancode: 0x24),
        "k": VirtualKeyInfo(vk: 0x4B, scancode: 0x25),
        "l": VirtualKeyInfo(vk: 0x4C, scancode: 0x26),
        ";": VirtualKeyInfo(vk: 0xBA, scancode: 0x27),
        "'": VirtualKeyInfo(vk: 0xDE, scancode: 0x28),
        "\\": VirtualKeyInfo(vk: 0xDC, scancode: 0x2B),
        "Shift": VirtualKeyInfo(vk: 0xA0, scancode: 0x2A),

        "z": VirtualKeyInfo(vk: 0x5A, scancode: 0x2C),
        "x": VirtualKeyInfo(vk: 0x58, scancode: 0x2D),
        "c": VirtualKeyInfo(vk: 0x43, scancode: 0x2E),
        "v": VirtualKeyInfo(vk: 0x56, scancode: 0x2F),
        "b": VirtualKeyInfo(vk: 0x42, scancode: 0x30),
        "n": VirtualKeyInfo(vk: 0x4E, scancode: 0x31),
        "m": VirtualKeyInfo(vk: 0x4D, scancode: 0x32),
        ",": VirtualKeyInfo(vk: 0xBC, scancode: 0x33),
        ".": VirtualKeyInfo(vk: 0xBE, scancode: 0x34),
        "/": VirtualKeyInfo(vk: 0xBF, scancode: 0x35),
        "Space": VirtualKeyInfo(vk: 0x20, scancode: 0x39),

        "Esc": VirtualKeyInfo(vk: 0x1B, scancode: 0x01),
        "Left": VirtualKeyInfo(vk: 0x25, scancode: 0xE04B),
        "Up": VirtualKeyInfo(vk: 0x26, scancode: 0xE048),
        "Down": VirtualKeyInfo(vk: 0x28, scancode: 0xE050),
        "Right": VirtualKeyInfo(vk: 0x27, scancode: 0xE04D)
    ]
    
    private let rows: [[String]] = [
        ["Esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]", "Enter"],
        ["Shift", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'", "\\"],
        ["Space", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "Left", "Up", "Down", "Right"]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKeyPress(key)
                        } label: {
                            Text(displayLabel(for: key))
                                .font(.system(size: 20, weight: .bold))
                                .frame(maxWidth: keyWidth(for: key))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(keyColor(for: key))
                    }
                }
            }
        }
        .padding(24)
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 40)
        .padding(.bottom, 30)
    }
    
    private func displayLabel(for key: String) -> String {
        if isShiftActive {
            switch key {
            case "q": return "Q"
            case "w": return "W"
            case "e": return "E"
            case "r": return "R"
            case "t": return "T"
            case "y": return "Y"
            case "u": return "U"
            case "i": return "I"
            case "o": return "O"
            case "p": return "P"
            case "a": return "A"
            case "s": return "S"
            case "d": return "D"
            case "f": return "F"
            case "g": return "G"
            case "h": return "H"
            case "j": return "J"
            case "k": return "K"
            case "l": return "L"
            case "z": return "Z"
            case "x": return "X"
            case "c": return "C"
            case "v": return "V"
            case "b": return "B"
            case "n": return "N"
            case "m": return "M"
            case "1": return "!"
            case "2": return "@"
            case "3": return "#"
            case "4": return "$"
            case "5": return "%"
            case "6": return "^"
            case "7": return "&"
            case "8": return "*"
            case "9": return "("
            case "0": return ")"
            case "-": return "_"
            case "=": return "+"
            case "[": return "{"
            case "]": return "}"
            case "\\": return "|"
            case ";": return ":"
            case "'": return "\""
            case ",": return "<"
            case ".": return ">"
            case "/": return "?"
            default: return key
            }
        }
        return key
    }
    
    private func keyWidth(for key: String) -> CGFloat {
        switch key {
        case "Space": return 200
        case "Backspace", "Enter", "Shift": return 120
        default: return 70
        }
    }
    
    private func keyColor(for key: String) -> Color {
        if key == "Shift" && isShiftActive {
            return .blue
        }
        switch key {
        case "Backspace", "Enter", "Esc": return .white.opacity(0.2)
        case "Space": return .white.opacity(0.3)
        case "Left", "Up", "Down", "Right": return .white.opacity(0.25)
        default: return .white.opacity(0.15)
        }
    }
    
    private func handleKeyPress(_ key: String) {
        if key == "Shift" {
            isShiftActive.toggle()
            return
        }
        
        guard let info = keysInfo[key] else { return }
        
        let mods: UInt16 = isShiftActive ? 0x0001 : 0
        
        Task {
            if isShiftActive {
                streamController.sendVirtualKeyEvent(down: true, vk: 0xA0, scancode: 0x2A, modifiers: 0)
                try? await Task.sleep(for: .milliseconds(15))
            }
            streamController.sendVirtualKeyEvent(down: true, vk: info.vk, scancode: info.scancode, modifiers: mods)
            try? await Task.sleep(for: .milliseconds(40))
            streamController.sendVirtualKeyEvent(down: false, vk: info.vk, scancode: info.scancode, modifiers: mods)
            if isShiftActive {
                try? await Task.sleep(for: .milliseconds(15))
                streamController.sendVirtualKeyEvent(down: false, vk: 0xA0, scancode: 0x2A, modifiers: 0)
            }
        }
    }
}
