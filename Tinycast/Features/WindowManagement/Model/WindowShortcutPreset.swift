import Carbon.HIToolbox
import Foundation

/// Another window manager's stock shortcuts. See docs/features/window-management.md.
enum WindowShortcutPreset: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case spectacle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: "Rectangle / Magnet"
        case .spectacle: "Spectacle"
        }
    }

    /// Physical key codes, as each app registers them, so a non-QWERTY layout matches too.
    var bindings: [WindowCommand.ID: HotKeyBinding] {
        switch self {
        case .rectangle:
            [
                .leftHalf: Self.combo(kVK_LeftArrow, controlKey | optionKey),
                .rightHalf: Self.combo(kVK_RightArrow, controlKey | optionKey),
                .topLeftQuarter: Self.combo(kVK_ANSI_U, controlKey | optionKey),
                .topRightQuarter: Self.combo(kVK_ANSI_I, controlKey | optionKey),
                .bottomLeftQuarter: Self.combo(kVK_ANSI_J, controlKey | optionKey),
                .bottomRightQuarter: Self.combo(kVK_ANSI_K, controlKey | optionKey),
                .maximize: Self.combo(kVK_Return, controlKey | optionKey),
                .center: Self.combo(kVK_ANSI_C, controlKey | optionKey)
            ]
        case .spectacle:
            [
                .leftHalf: Self.combo(kVK_LeftArrow, optionKey | cmdKey),
                .rightHalf: Self.combo(kVK_RightArrow, optionKey | cmdKey),
                .topLeftQuarter: Self.combo(kVK_LeftArrow, controlKey | cmdKey),
                .topRightQuarter: Self.combo(kVK_RightArrow, controlKey | cmdKey),
                .bottomLeftQuarter: Self.combo(kVK_LeftArrow, controlKey | shiftKey | cmdKey),
                .bottomRightQuarter: Self.combo(kVK_RightArrow, controlKey | shiftKey | cmdKey),
                .maximize: Self.combo(kVK_ANSI_F, optionKey | cmdKey),
                .center: Self.combo(kVK_ANSI_C, optionKey | cmdKey)
            ]
        }
    }

    /// Commands outside a preset don't count, since applying one never touches them.
    static func matching(_ current: [WindowCommand.ID: HotKeyBinding]) -> WindowShortcutPreset? {
        allCases.first { preset in preset.bindings.allSatisfy { current[$0.key] == $0.value } }
    }

    private static func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
    }
}

/// What applying a preset changes, worked out before anything is written.
struct WindowShortcutPresetPlan: Equatable, Sendable {
    /// Preset entries that differ from what the command holds now.
    let assignments: [WindowCommand.ID: HotKeyBinding]
    /// Commands the preset doesn't assign that hold a key it gives to another command.
    let displaced: [WindowCommand.ID]
    /// Every command that loses a shortcut the user set, in catalog order.
    let overwritten: [WindowCommand.ID]

    init(preset: WindowShortcutPreset, current: [WindowCommand.ID: HotKeyBinding]) {
        let assignments = preset.bindings.filter { current[$0.key] != $0.value }
        let claimed = Set(assignments.values)
        let displaced = WindowCommand.ID.allCases.filter { id in
            guard assignments[id] == nil, let binding = current[id] else { return false }
            return claimed.contains(binding)
        }
        self.assignments = assignments
        self.displaced = displaced
        overwritten = WindowCommand.ID.allCases.filter { id in
            (assignments[id] != nil && current[id] != nil) || displaced.contains(id)
        }
    }
}
