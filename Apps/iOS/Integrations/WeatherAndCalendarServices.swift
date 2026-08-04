import Foundation
import SunnieShared
#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(EventKit)
import EventKit
#endif

/// WeatherKit lookup for trip screens (TRAVEL_AND_FLIGHT_ATTENDANT.md §9).
///
/// **Every ordinary failure returns nil rather than throwing.** Offline, no
/// entitlement, a place with no coordinate — none of those is something the user
/// needs told about, and a trip screen that shows an error where the weather
/// would be is worse than one that simply shows no weather (§16).
///
/// Results are cached briefly, because a trip screen that refetches on every
/// appearance would burn the WeatherKit quota on nothing.
///
/// **Attribution travels with the data.** Apple requires it, and carrying it in
/// `WeatherSummary` rather than leaving it to the view means the data cannot be
/// displayed without it.
actor SunnieWeatherService: WeatherProviding {

    private let log = SunnieLog(category: .integrations)

    /// How long a reading stays good. Weather does not change usefully faster
    /// than this, and a trip screen may be opened repeatedly in a minute.
    private static let cacheLifetime: TimeInterval = 15 * 60

    private struct CacheEntry {
        let summary: WeatherSummary
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]

    func summary(latitude: Double, longitude: Double) async -> WeatherSummary? {
        let key = Self.cacheKey(latitude: latitude, longitude: longitude)

        if let cached = cache[key],
           Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached.summary
        }

        #if canImport(WeatherKit) && canImport(CoreLocation)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            // Fully qualified: WeatherKit's own type is also called
            // WeatherService, and an unqualified reference here resolves to
            // this actor instead — the same collision that forced `Clock` to
            // become `SunnieClock` (ADR-009).
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            let today = weather.dailyForecast.first

            let summary = WeatherSummary(
                condition: Self.map(weather.currentWeather.condition),
                temperatureCelsius: weather.currentWeather.temperature
                    .converted(to: .celsius).value,
                highCelsius: today?.highTemperature.converted(to: .celsius).value,
                lowCelsius: today?.lowTemperature.converted(to: .celsius).value,
                fetchedAt: Date(),
                attributionText: "Weather",
                attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")
            )

            cache[key] = CacheEntry(summary: summary, fetchedAt: Date())
            return summary
        } catch {
            // Offline, no entitlement, rate-limited. All ordinary; none worth
            // surfacing.
            log.debug("Weather is unavailable right now.")
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func cacheKey(latitude: Double, longitude: Double) -> String {
        // Rounded to about a kilometre: two places that close share weather, and
        // caching them separately would double the requests for nothing.
        String(format: "%.2f,%.2f", latitude, longitude)
    }

    #if canImport(WeatherKit)
    /// Collapses WeatherKit's long condition list into the handful the UI draws.
    ///
    /// Anything unrecognised becomes `.unknown` rather than being guessed at — a
    /// wrong icon reads as a bug, a neutral one reads as "no detail".
    private static func map(_ condition: WeatherCondition) -> WeatherSummary.Condition {
        switch condition {
        case .clear, .mostlyClear, .hot:
            .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy:
            .cloudy
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingRain, .freezingDrizzle:
            .rain
        case .snow, .heavySnow, .flurries, .sleet, .wintryMix, .blizzard, .blowingSnow, .sunFlurries, .frigid:
            .snow
        case .windy, .breezy, .blowingDust:
            .wind
        case .foggy, .haze, .smoky:
            .fog
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hurricane, .tropicalStorm, .hail:
            .storm
        @unknown default:
            .unknown
        }
    }
    #endif
}

/// EventKit access for linking trips to calendar events
/// (TRAVEL_AND_FLIGHT_ATTENDANT.md §10).
///
/// **Entirely optional.** The app is fully usable with the calendar denied, and
/// the trip stays the source of truth for everything Sunnie Days-specific
/// whatever the calendar says. Permission is never requested at launch — only
/// when the user taps something that needs it.
actor SunnieCalendarService: CalendarProviding {

    private let log = SunnieLog(category: .integrations)

    #if canImport(EventKit)
    private let store = EKEventStore()
    #endif

    func authorizationStatus() async -> CalendarAuthorization {
        #if canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .writeOnly: return .writeOnly
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    /// Asks for full access, because reading is what makes the link useful —
    /// detecting that an event moved is the whole point of linking one (§10).
    func requestAccess() async -> CalendarAuthorization {
        #if canImport(EventKit)
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            log.debug("Calendar access could not be requested.")
            return .denied
        }
        #else
        return .denied
        #endif
    }

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        #if canImport(EventKit)
        guard await authorizationStatus() == .authorized else { return [] }
        guard end > start else { return [] }

        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        )
        return store.events(matching: predicate).map {
            CalendarEvent(
                id: $0.eventIdentifier ?? UUID().uuidString,
                title: $0.title ?? "",
                startsAt: $0.startDate,
                endsAt: $0.endDate,
                isAllDay: $0.isAllDay,
                location: $0.location
            )
        }
        #else
        return []
        #endif
    }

    /// Creates an event and returns its identifier.
    ///
    /// A failure costs a calendar entry, never the trip — the caller stores the
    /// identifier only when there is one, and the trip is already saved by then.
    func createEvent(
        title: String,
        startsAt: Date,
        endsAt: Date,
        notes: String?
    ) async -> String? {
        #if canImport(EventKit)
        let status = await authorizationStatus()
        guard status == .authorized || status == .writeOnly else { return nil }
        guard let calendar = store.defaultCalendarForNewEvents else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startsAt
        // A zero-length event is invalid and would be rejected; a trip that has
        // only a start date gets a single all-day entry instead.
        event.endDate = max(endsAt, startsAt.addingTimeInterval(60))
        event.notes = notes
        event.calendar = calendar

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            log.debug("A calendar event could not be created.")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Reads a linked event back, so the trip screen can notice it moved.
    ///
    /// Nil when it has been deleted externally, which the UI presents as the link
    /// being gone rather than as an error.
    func event(withIdentifier identifier: String) async -> CalendarEvent? {
        #if canImport(EventKit)
        guard await authorizationStatus() == .authorized else { return nil }
        guard let event = store.event(withIdentifier: identifier) else { return nil }

        return CalendarEvent(
            id: identifier,
            title: event.title ?? "",
            startsAt: event.startDate,
            endsAt: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location
        )
        #else
        return nil
        #endif
    }
}
