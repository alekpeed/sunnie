import Foundation
import SunnieShared

/// Seeds a small starter jungle on first launch (task E2-01).
///
/// This exists so the vertical slice has something to act on before the plant
/// editor is built in Phase 4. It runs only when the store is empty, so it never
/// overwrites real data, and every plant it creates is an ordinary record the
/// user can rename, reschedule, or archive.
///
/// The seed is intentionally small. Performance work against a realistic 50–100
/// plant collection is a Phase 4 task with its own fixtures.
enum SampleData {

    @MainActor
    static func seedIfNeeded(dependencies: AppDependencies) async {
        let log = SunnieLog(category: .persistence)
        do {
            let existing = try await dependencies.plantRepository
                .allPlants(includingArchived: true)
            guard existing.isEmpty else { return }

            let now = dependencies.clock.now
            let calendar = dependencies.clock.calendar
            let timeZone = dependencies.clock.timeZone

            let livingRoom = PlantLocation(
                name: "Living room", room: "Living room",
                lightNotes: "Bright, indirect", sortOrder: 0
            )
            let bedroom = PlantLocation(
                name: "Bedroom", room: "Bedroom",
                lightNotes: "Lower light", sortOrder: 1
            )
            try await dependencies.plantRepository.save(livingRoom)
            try await dependencies.plantRepository.save(bedroom)

            let seeds: [(name: String, species: String, location: UUID,
                         light: LightProfile, difficulty: CareDifficulty,
                         intervalDays: Int, dueOffsetDays: Int)] = [
                ("Monstera", "Monstera deliciosa", livingRoom.id,
                 .indirectBright, .easy, 7, -2),
                ("Bird of Paradise", "Strelitzia nicolai", livingRoom.id,
                 .directSun, .moderate, 6, 0),
                ("Fiddle Leaf Fig", "Ficus lyrata", livingRoom.id,
                 .indirectBright, .demanding, 8, 1),
                ("Pothos", "Epipremnum aureum", bedroom.id,
                 .lowLight, .easy, 10, 3),
                ("Calathea", "Calathea orbifolia", bedroom.id,
                 .dappled, .demanding, 5, 4)
            ]

            for seed in seeds {
                let plant = Plant(
                    name: seed.name,
                    speciesName: seed.species,
                    locationID: seed.location,
                    lightProfile: seed.light,
                    difficulty: seed.difficulty,
                    acquiredDate: calendar.date(byAdding: .month, value: -8, to: now),
                    status: .active,
                    // A random token rather than the plant's ID, so a printed QR
                    // code cannot be used to enumerate records
                    // (PLANT_CARE.md §11).
                    qrToken: UUID().uuidString,
                    createdAt: now,
                    modifiedAt: now
                )
                try await dependencies.plantRepository.save(plant)

                let nextDue = Self.dueDate(
                    offsetDays: seed.dueOffsetDays,
                    from: now,
                    calendar: calendar,
                    timeZone: timeZone
                )
                let schedule = PlantCareSchedule(
                    plantID: plant.id,
                    careType: .water,
                    recurrence: .everyDays(seed.intervalDays),
                    seasonalModifier: SeasonalModifier(
                        springMultiplier: 1,
                        summerMultiplier: 0.85,
                        autumnMultiplier: 1.1,
                        winterMultiplier: 1.4
                    ),
                    preferredHour: 9,
                    isEnabled: true,
                    lastCompletedAt: nil,
                    nextDueDate: nextDue
                )
                try await dependencies.plantRepository.save(schedule)
            }

            await dependencies.summaryProvider.invalidate()

            // Invalidating the cache is not enough on its own, and the gap it
            // leaves was invisible until a UI test walked first launch.
            //
            // Today builds its summary from the store during its own `.task`,
            // which runs alongside this one — and wins, because seeding has ten
            // writes to get through first. So Today caches a summary of an empty
            // jungle, and clearing the provider's cache afterwards changes
            // nothing on screen: nothing asks it to read again. A brand-new user
            // saw "No plants yet" sitting above five plants that existed,
            // until they switched tabs and came back.
            //
            // So seeding says what it did, in the same typed vocabulary every
            // other feature uses (TECHNICAL_ARCHITECTURE.md §6). One event
            // rather than one per plant: the listeners rebuild a whole summary
            // either way, and five would just mean five rebuilds.
            await dependencies.eventBus.publish(
                DomainEvent(
                    type: .plantAdded,
                    occurredAt: now,
                    sourceEntityID: nil
                )
            )
            log.info("Seeded \(seeds.count) sample plants on first launch.")
        } catch {
            // A failed seed leaves an empty jungle, which the empty state already
            // handles gracefully.
            log.error("Sample data could not be seeded.")
        }
    }

    /// Places a due date at the preferred hour, `offsetDays` from today.
    private static func dueDate(
        offsetDays: Int,
        from now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date {
        var zoned = calendar
        zoned.timeZone = timeZone

        let day = zoned.date(byAdding: .day, value: offsetDays, to: now) ?? now
        var components = zoned.dateComponents([.year, .month, .day], from: day)
        components.hour = 9
        components.timeZone = timeZone
        return zoned.date(from: components) ?? day
    }
}
