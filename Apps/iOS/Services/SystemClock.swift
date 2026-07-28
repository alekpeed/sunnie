import Foundation
import SunnieShared

/// The production clock. Everything time-dependent reads through `Clock`, so
/// tests substitute a fixed one rather than depending on when they run.
struct SystemClock: SunnieClock {
    var now: Date { Date() }
    var timeZone: TimeZone { TimeZone.current }
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar
    }
}

/// A clock pinned to a fixed instant.
///
/// Lives in the app target rather than a test file because SwiftUI previews use
/// it too — a preview of the night presentation should not require waiting until
/// night.
struct FixedClock: SunnieClock {
    let now: Date
    let timeZone: TimeZone

    init(now: Date, timeZone: TimeZone = .current) {
        self.now = now
        self.timeZone = timeZone
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
