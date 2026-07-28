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

    let plantRepository: any PlantRepository
    let careEventRepository: any PlantCareEventRepository
    let progressionRepository: any ProgressionRepository
    let preferencesRepository: any PreferencesRepository
    let pendingWatchActionRepository: any PendingWatchActionRepository

    let progressionEngine: ProgressionEngine
    let summaryProvider: PlantSummaryProvider
    let eventBus: DomainEventBus

    let notificationService: NotificationService
    let audioService: AudioService
    let haptics: HapticService

    let logPlantCare: LogPlantCare

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

        let plants = SwiftDataPlantRepository(modelContainer: modelContainer)
        let events = SwiftDataPlantCareEventRepository(modelContainer: modelContainer)
        let progression = SwiftDataProgressionRepository(modelContainer: modelContainer)
        let preferences = SwiftDataPreferencesRepository(modelContainer: modelContainer)
        let watchQueue = SwiftDataPendingWatchActionRepository(modelContainer: modelContainer)

        self.plantRepository = plants
        self.careEventRepository = events
        self.progressionRepository = progression
        self.preferencesRepository = preferences
        self.pendingWatchActionRepository = watchQueue

        self.progressionEngine = ProgressionEngine(repository: progression)
        self.summaryProvider = PlantSummaryProvider(
            plantRepository: plants, clock: clock
        )
        self.eventBus = DomainEventBus()

        self.notificationService = NotificationService()
        self.audioService = AudioService()
        self.haptics = HapticService()

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
            clock: clock,
            deviceID: deviceID
        )

        if enableWatchConnectivity {
            configureWatchConnectivity()
        }
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
