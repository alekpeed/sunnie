import SunnieShared

extension ContextAction {
    /// Maps a platform-neutral context action to the iPhone navigation graph.
    /// `tellSunnie` is presented as a sheet by its host surface and therefore
    /// intentionally has no `AppRoute`.
    var appRoute: AppRoute? {
        switch self {
        case .openTravel: .travel
        case .openTrip(let id): .trip(id)
        case .openPacking(let id): .packing(id)
        case .openChecklist(let id, let phase): .tripChecklist(id, phase.rawValue)
        case .openPlantCoverage(let id): .plantCoverage(id)
        case .openJungle: .jungle
        case .openJungleDue: .jungleDue
        case .openMeals: .meals
        case .openGames: .games
        case .openWellness: .wellness
        case .openJournal: .journal
        case .openSunnieHome: .sunnieHome
        case .openCollections: .collections
        case .tellSunnie: nil
        }
    }
}
