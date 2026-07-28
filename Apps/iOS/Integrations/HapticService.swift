import Foundation
import SunnieShared
#if canImport(UIKit)
import UIKit
#endif

/// Confirmation feedback.
///
/// Separate from audio so it can be turned off independently, and deliberately
/// limited to three intensities. There is no repeating or escalating pattern:
/// haptic pressure would be the physical form of the nagging the tone rules
/// forbid (VISUAL_DESIGN_SYSTEM.md §11).
@MainActor
final class HapticService: HapticFeedback {

    private var isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    nonisolated func selection() {
        Task { @MainActor in
            guard isEnabled else { return }
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }

    nonisolated func success() {
        Task { @MainActor in
            guard isEnabled else { return }
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
    }

    /// Only for genuine attention states. Routine reminders use `selection` or
    /// nothing at all.
    nonisolated func attention() {
        Task { @MainActor in
            guard isEnabled else { return }
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
        }
    }
}

struct NoOpHaptics: HapticFeedback {
    func selection() {}
    func success() {}
    func attention() {}
}
