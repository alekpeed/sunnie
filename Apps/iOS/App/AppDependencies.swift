import Foundation
import Observation
import SwiftData
import SunnieShared

/// The composition root.
///
/// This is the only type that knows about concrete implementations. Features
/// receive protocols and use cases through initializers and never construct their
/// own dependencies, which is what makes them testable in isolation and what
/// keeps a feature from reaching into another feature's storage
/// (TECHNICAL_ARCHITECTURE.md §8).
@MainActor
@Observable
final class AppDependencies {

    let modelContainer: ModelContainer
    /// True when the on-disk store could not be opened and this session is
    /// running in memory. The UI must tell the user their work is not being saved.
    let isEphemeralStorage: Bool

    let clock: any SunnieClock
    let deviceID: DeviceID

    let contentRegistry: ContentRegistry
    let themeEngine: ThemeEngine
    let timeEngine: TimePhaseEngine
    let messageService: SunnieMessageService
    let affirmationService: AffirmationService

    let plantRepository: any PlantRepository
    let careEventRepository: any PlantCareEventRepository
    let progressionRepository: any ProgressionRepository
    let preferencesRepository: any PreferencesRepository
    let pendingWatchActionRepository: any PendingWatchActionRepository
    let wellnessRepository: any WellnessRepository
    let journalRepository: any JournalRepository
    let mediaRepository: any MediaRepository
    let reminderRepository: any ReminderRepository
    let plantHealthRepository: any PlantHealthRepository
    let travelRepository: any TravelRepository

    let progressionEngine: ProgressionEngine
    let summaryProvider: PlantSummaryProvider
    let wellnessSummaryProvider: WellnessSummaryProvider
    let eventBus: DomainEventBus
    let reminderScheduler: ReminderScheduler

    let notificationService: NotificationService
    let audioService: AudioService
    let noiseEngine: any NoiseGenerating
    let weatherProvider: any WeatherProviding
    let calendarProvider: any CalendarProviding
    let haptics: HapticService

    let logPlantCare: LogPlantCare
    let logBulkCare: LogBulkCare
    let managePlant: ManagePlant
    let managePlantHealth: ManagePlantHealth
    let planTravelCoverage: PlanTravelCoverage
    let exportJungle: ExportJungle
    let manageTrip: ManageTrip
    let managePacking: ManagePacking
    let manageChecklists: ManageChecklists
    let recordWellnessCheckIn: RecordWellnessCheckIn
    let manageWellnessSession: ManageWellnessSession
    let manageJournalEntry: ManageJournalEntry
    let attachMedia: AttachMedia

    // @ObservationIgnored keeps these as plain stored properties. The
    // @Observable macro turns a `var` into a computed property whose setter
    // touches `self`, which cannot be assigned before every stored property is
    // initialized — and `watchSync` is assigned partway through `init`. Nothing
    // here is observable state anyway; the dependency graph is fixed after
    // composition.
    @ObservationIgnored private(set) var watchSync: any WatchSyncing
    @ObservationIgnored private(set) var watchProcessor: WatchActionProcessor?
    @ObservationIgnored private var watchConnectivity: WatchConnectivityService?

    init(
        modelContainer: ModelContainer,
        isEphemeralStorage: Bool = false,
        clock: any SunnieClock = SystemClock(),
        deviceID: DeviceID = .currentDevice,
        enableWatchConnectivity: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.isEphemeralStorage = isEphemeralStorage
        self.clock = clock
        self.deviceID = deviceID

        let registry = ContentRegistry.builtIn()
        self.contentRegistry = registry
        self.themeEngine = ThemeEngine(registry: registry)
        self.timeEngine = TimePhaseEngine(calendar: clock.calendar)
        self.messageService = SunnieMessageService(registry: registry)
        self.affirmationService = AffirmationService(pack: registry.wellnessPack)

        let plants = SwiftDataPlantRepository(modelContainer: modelContainer)
        let events = SwiftDataPlantCareEventRepository(modelContainer: modelContainer)
        let progression = SwiftDataProgressionRepository(modelContainer: modelContainer)
        let preferences = SwiftDataPreferencesRepository(modelContainer: modelContainer)
        let watchQueue = SwiftDataPendingWatchActionRepository(modelContainer: modelContainer)
        let wellness = SwiftDataWellnessRepository(modelContainer: modelContainer)
        let journal = SwiftDataJournalRepository(modelContainer: modelContainer)
        let media = SwiftDataMediaRepository(modelContainer: modelContainer)
        let reminders = SwiftDataReminderRepository(modelContainer: modelContainer)
        let plantHealth = SwiftDataPlantHealthRepository(modelContainer: modelContainer)
        let travel = SwiftDataTravelRepository(modelContainer: modelContainer)

        self.plantRepository = plants
        self.careEventRepository = events
        self.progressionRepository = progression
        self.preferencesRepository = preferences
        self.pendingWatchActionRepository = watchQueue
        self.wellnessRepository = wellness
        self.journalRepository = journal
        self.mediaRepository = media
        self.reminderRepository = reminders
        self.plantHealthRepository = plantHealth
        self.travelRepository = travel

        self.progressionEngine = ProgressionEngine(repository: progression)
        self.summaryProvider = PlantSummaryProvider(
            plantRepository: plants, clock: clock
        )
        self.wellnessSummaryProvider = WellnessSummaryProvider(
            repository: wellness, clock: clock
        )
        self.eventBus = DomainEventBus()

        self.notificationService = NotificationService()
        self.audioService = AudioService()
        self.noiseEngine = NoiseEngine()
        self.weatherProvider = SunnieWeatherService()
        self.calendarProvider = SunnieCalendarService()
        self.haptics = HapticService()

        self.reminderScheduler = ReminderScheduler(
            repository: reminders,
            notifications: notificationService,
            preferencesRepository: preferences,
            messageProvider: messageService,
            timeResolver: timeEngine,
            clock: clock
        )

        self.attachMedia = AttachMedia(repository: media, clock: clock)

        // The Watch bridge is created after the use case it feeds, so the
        // dependency runs one way: connectivity delivers into the processor,
        // which calls the use case. Nothing calls back out to connectivity.
        let placeholderSync = UnavailableWatchSync()
        self.watchSync = placeholderSync

        self.logPlantCare = LogPlantCare(
            plantRepository: plants,
            careEventRepository: events,
            progressionEngine: progressionEngine,
            summaryProvider: summaryProvider,
            messageProvider: messageService,
            timeResolver: timeEngine,
            preferencesRepository: preferences,
            watchSync: WatchSyncBox(),
            eventPublisher: eventBus,
            reminders: reminderScheduler,
            clock: clock,
            deviceID: deviceID
        )

        self.logBulkCare = LogBulkCare(logCare: logPlantCare, clock: clock)

        self.managePlant = ManagePlant(
            plantRepository: plants,
            careEventRepository: events,
            progressionEngine: progressionEngine,
            summaryProvider: summaryProvider,
            reminders: reminderScheduler,
            eventPublisher: eventBus,
            clock: clock
        )

        self.managePlantHealth = ManagePlantHealth(
            repository: plantHealth,
            progressionEngine: progressionEngine,
            clock: clock,
            deviceID: deviceID
        )

        self.planTravelCoverage = PlanTravelCoverage(
            plantRepository: plants,
            careEventRepository: events,
            healthRepository: plantHealth,
            progressionEngine: progressionEngine,
            clock: clock
        )

        self.exportJungle = ExportJungle(
            plantRepository: plants,
            careEventRepository: events,
            healthRepository: plantHealth,
            clock: clock
        )

        self.manageTrip = ManageTrip(
            repository: travel,
            progressionEngine: progressionEngine,
            eventPublisher: eventBus,
            clock: clock
        )

        self.managePacking = ManagePacking(repository: travel, clock: clock)
        self.manageChecklists = ManageChecklists(repository: travel, clock: clock)

        self.recordWellnessCheckIn = RecordWellnessCheckIn(
            repository: wellness,
            preferencesRepository: preferences,
            progressionEngine: progressionEngine,
            messageProvider: messageService,
            timeResolver: timeEngine,
            eventPublisher: eventBus,
            summaryProvider: wellnessSummaryProvider,
            clock: clock,
            deviceID: deviceID
        )

        self.manageWellnessSession = ManageWellnessSession(
            repository: wellness,
            summaryProvider: wellnessSummaryProvider,
            audio: audioService,
            clock: clock,
            deviceID: deviceID
        )

        self.manageJournalEntry = ManageJournalEntry(
            repository: journal,
            eventPublisher: eventBus,
            clock: clock
        )

        if enableWatchConnectivity {
            configureWatchConnectivity()
        }
    }

    /// Connects delivered notifications to routing and to the use cases that
    /// honour their action buttons.
    ///
    /// Called once at launch. Registering the categories is what makes "Done",
    /// "Later", and "Not today" appear at all, and it must happen before any
    /// notification is delivered — a request scheduled against an unregistered
    /// category arrives as a plain banner with no buttons.
    ///
    /// This does not ask for permission. The app is fully usable with
    /// notifications denied, and the request lives in Settings behind a button
    /// the user chooses to press (ONBOARDING_SETTINGS_AND_PERMISSIONS.md §7).
    func configureNotifications(
        onRoute: @escaping @MainActor @Sendable (AppRoute) -> Void
    ) {
        notificationService.registerCategories()

        notificationService.onRouteRequested = { routeString in
            // An unrecognised route resolves to nothing rather than to a default
            // screen: landing somewhere unexpected is more confusing than the tap
            // simply opening the app.
            guard
                let url = URL(string: routeString),
                let route = DeepLinkParser.route(from: url)
            else { return }
            Task { @MainActor in onRoute(route) }
        }

        notificationService.onAction = { action in
            Task { @MainActor [weak self] in
                await self?.handle(action)
            }
        }
    }

    /// Honours what the user did to a notification.
    ///
    /// "Done" logs the real care action rather than only noting the tap, which is
    /// why the reminder carries the plant and care type in its payload. The action
    /// goes through the same use case as a tap in the app, so it is idempotent,
    /// earns progression once, and reaches the Watch — pressing "Done" on the
    /// phone and then watering in the app within the same minute records one event
    /// (ADR-013).
    private func handle(_ action: DeliveredNotificationAction) async {
        await reminderScheduler.recordResponse(
            reminderID: action.reminderID, response: action.response
        )

        guard action.response == .completed else { return }
        guard
            let plantID = action.payload[NotificationPayloadKeys.plantID]
                .flatMap(UUID.init(uuidString:)),
            let careType = action.payload[NotificationPayloadKeys.careType]
                .flatMap(CareType.init(storageKey:))
        else { return }

        let scheduleID = action.payload[NotificationPayloadKeys.scheduleID]
            .flatMap(UUID.init(uuidString:))

        // A failure here is not surfaced. The user has already put the phone
        // down; the task simply stays due, which is the honest outcome.
        _ = try? await logPlantCare(
            plantID: plantID, careType: careType, scheduleID: scheduleID
        )
    }

    /// Launch housekeeping that must not block the first frame.
    ///
    /// Both are cheap and idempotent: journal entries past the thirty-day restore
    /// window are destroyed, and media files whose owner is gone are swept up.
    func performLaunchHousekeeping() async {
        _ = try? await manageJournalEntry.purgeExpired()
        _ = try? await mediaRepository.deleteOrphans()
    }

    /// Convenience initializer for previews and tests: a fresh in-memory store
    /// and no Watch session.
    static func inMemory(clock: any SunnieClock = SystemClock()) -> AppDependencies {
        do {
            return AppDependencies(
                modelContainer: try ModelContainerFactory.make(storage: .inMemory),
                clock: clock,
                enableWatchConnectivity: false
            )
        } catch {
            // An in-memory container failing means the schema is invalid, which
            // no runtime handling can recover from.
            fatalError("In-memory container could not be created: \(error)")
        }
    }

    private func configureWatchConnectivity() {
        let processor = WatchActionProcessor(
            queue: pendingWatchActionRepository,
            logCare: logPlantCare,
            clock: clock
        )
        self.watchProcessor = processor

        let connectivity = WatchConnectivityService { payload in
            await processor.receive(payload)
        }
        self.watchConnectivity = connectivity
        self.watchSync = connectivity
        WatchSyncBox.shared = connectivity
        connectivity.activate()
    }

    /// Drains anything the Watch sent while the app was not running.
    func processPendingWatchActions() async {
        await watchProcessor?.processPending()
    }
}

/// Indirection that lets `LogPlantCare` be constructed before the Watch session
/// exists.
///
/// The use case needs a `WatchSyncing` at init, but the connectivity service
/// needs the use case in order to deliver incoming actions to it. Rather than
/// making either optional and littering both with nil checks, the box resolves
/// to whichever implementation is live at call time and degrades to "no Watch"
/// until one is.
struct WatchSyncBox: WatchSyncing {
    /// Set once during composition. Not intended to be mutated afterwards.
    nonisolated(unsafe) static var shared: (any WatchSyncing)?

    var isSupported: Bool { Self.shared?.isSupported ?? false }
    var isReachable: Bool { Self.shared?.isReachable ?? false }

    func updateApplicationContext(_ context: WatchApplicationContext) async {
        await Self.shared?.updateApplicationContext(context)
    }
}

extension DeviceID {
    /// A stable per-installation identifier used for source-device metadata.
    ///
    /// Generated locally and stored in user defaults — it identifies "this
    /// install" for sync reconciliation, never the user or the hardware, and it
    /// never leaves the user's own devices.
    static var currentDevice: DeviceID {
        let key = "sunnie.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return DeviceID(rawValue: existing)
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return DeviceID(rawValue: generated)
    }
}
