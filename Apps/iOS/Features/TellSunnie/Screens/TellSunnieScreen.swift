import AVFoundation
import Foundation
import Observation
import Speech
import SwiftUI
import SunnieShared

struct TellSunnieResponse: Equatable {
    let text: String
    let action: ContextAction?
    let actionTitle: String?
    let openImmediately: Bool

    init(
        text: String,
        action: ContextAction? = nil,
        actionTitle: String? = nil,
        openImmediately: Bool = false
    ) {
        self.text = text
        self.action = action
        self.actionTitle = actionTitle
        self.openImmediately = openImmediately
    }
}

/// Executes Tell Sunnie requests through the same use cases used by ordinary
/// screens. It is an intent router, never a parallel persistence layer.
@MainActor
@Observable
final class TellSunnieModel {
    private(set) var response: TellSunnieResponse?
    private(set) var isWorking = false

    private let dependencies: AppDependencies
    private let appState: AppState

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    @discardableResult
    func submit(_ rawInput: String) async -> TellSunnieResponse {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return set(TellSunnieResponse(text: "Tell me what you want to remember, find, or do."))
        }

        isWorking = true
        defer { isWorking = false }

        let intent = TellSunnieParser.parse(input)
        let result: TellSunnieResponse

        switch intent {
        case .open(let destination):
            result = openResponse(for: destination)

        case .recordPlantCare(let careType, let plantQuery):
            result = await recordPlantCare(careType: careType, plantQuery: plantQuery)

        case .addPackingItem(let name, let category):
            result = await addPackingItem(name: name, category: category)

        case .askTripPreparation:
            await appState.refreshCurrentContext()
            result = tripPreparationResponse()

        case .askPlantCare:
            await appState.refreshCurrentContext()
            result = plantCareResponse()

        case .unknown:
            result = TellSunnieResponse(
                text: "I’m not certain what you meant yet. I can already open parts of Sunnie Days, log common plant care, add something to Flight Mode packing, and summarize current trip or plant context."
            )
        }

        return set(result)
    }

    private func set(_ value: TellSunnieResponse) -> TellSunnieResponse {
        response = value
        return value
    }

    private func openResponse(for destination: AssistantDestination) -> TellSunnieResponse {
        let mapping: (String, ContextAction) = switch destination {
        case .travel: ("Travel", .openTravel)
        case .plants: ("your Jungle", .openJungle)
        case .meals: ("Meals", .openMeals)
        case .games: ("Games", .openGames)
        case .wellness: ("Wellness", .openWellness)
        case .journal: ("Journal", .openJournal)
        case .home: ("Sunnie’s Home", .openSunnieHome)
        case .collections: ("your rewards and collection", .openCollections)
        }

        return TellSunnieResponse(
            text: "Opening \(mapping.0).",
            action: mapping.1,
            openImmediately: true
        )
    }

    private func recordPlantCare(
        careType: CareType,
        plantQuery: String
    ) async -> TellSunnieResponse {
        let plants = (try? await dependencies.plantRepository.allPlants(includingArchived: false)) ?? []
        let matches = matchingPlants(query: plantQuery, plants: plants)

        guard matches.count == 1, let plant = matches.first else {
            if matches.isEmpty {
                return TellSunnieResponse(
                    text: "I couldn’t match “\(plantQuery)” to one of your plants. Nothing was changed.",
                    action: .openJungle,
                    actionTitle: "Open Jungle"
                )
            }
            return TellSunnieResponse(
                text: "I found more than one plant that could mean “\(plantQuery)”. Nothing was changed.",
                action: .openJungle,
                actionTitle: "Choose in Jungle"
            )
        }

        do {
            _ = try await dependencies.logPlantCare(
                plantID: plant.id,
                careType: careType,
                scheduleID: nil
            )
            await appState.refreshCurrentContext()
            dependencies.haptics.success()
            return TellSunnieResponse(
                text: "Logged \(careDescription(careType)) for \(plant.displayName).",
                action: .openJungle,
                actionTitle: "Open Jungle"
            )
        } catch {
            return TellSunnieResponse(
                text: "That didn’t save just now, so I left everything unchanged.",
                action: .openJungle,
                actionTitle: "Open Jungle"
            )
        }
    }

    private func addPackingItem(
        name: String,
        category: PackingCategory
    ) async -> TellSunnieResponse {
        await appState.refreshCurrentContext()
        guard let flight = appState.currentContext.flightMode else {
            return TellSunnieResponse(
                text: "There isn’t a work trip in Flight Mode right now, so I didn’t guess which packing list you meant.",
                action: .openTravel,
                actionTitle: "Open Travel"
            )
        }

        do {
            let item = PackingItem(
                tripID: flight.tripID,
                name: name,
                category: category
            )
            _ = try await dependencies.managePacking.save(item)
            await appState.refreshCurrentContext()
            dependencies.haptics.success()
            return TellSunnieResponse(
                text: "Added \(name) to \(flight.tripTitle) packing.",
                action: .openPacking(flight.tripID),
                actionTitle: "Open Packing"
            )
        } catch {
            return TellSunnieResponse(
                text: "I couldn’t add that just now, so the packing list is unchanged.",
                action: .openPacking(flight.tripID),
                actionTitle: "Open Packing"
            )
        }
    }

    private func tripPreparationResponse() -> TellSunnieResponse {
        guard let flight = appState.currentContext.flightMode else {
            return TellSunnieResponse(
                text: "There isn’t a work trip in Flight Mode right now.",
                action: .openTravel,
                actionTitle: "Open Travel"
            )
        }

        var facts: [String] = []
        if flight.packingCount > 0 {
            facts.append("\(flight.packedCount) of \(flight.packingCount) packing items are checked")
        }
        if flight.checklistCount > 0 {
            facts.append("\(flight.checklistDoneCount) of \(flight.checklistCount) personal checklist items are checked")
        }
        if flight.plantCoverageUndecidedCount > 0 {
            let count = flight.plantCoverageUndecidedCount
            facts.append(count == 1
                ? "1 plant coverage decision is still undecided"
                : "\(count) plant coverage decisions are still undecided")
        }
        if flight.plannedMealsTodayCount > 0 {
            facts.append("\(flight.plannedMealsTodayCount) meal plans are on today")
        }

        let prefix = flight.destinationName.map { "For \($0): " } ?? "For \(flight.tripTitle): "
        let text = facts.isEmpty
            ? "\(prefix)I don’t see any current packing, checklist, plant-coverage, or meal-plan items to summarize."
            : prefix + facts.joined(separator: "; ") + "."

        return TellSunnieResponse(
            text: text,
            action: .openTrip(flight.tripID),
            actionTitle: "Open Trip"
        )
    }

    private func plantCareResponse() -> TellSunnieResponse {
        guard let summary = appState.currentContext.plantSummary else {
            return TellSunnieResponse(
                text: "I couldn’t read the Jungle summary just now. Your plant records are still there.",
                action: .openJungle,
                actionTitle: "Open Jungle"
            )
        }

        let count = summary.actionableTasks.count
        if count == 0 {
            return TellSunnieResponse(
                text: "There aren’t any care items in the current Jungle window.",
                action: .openJungle,
                actionTitle: "Open Jungle"
            )
        }

        return TellSunnieResponse(
            text: count == 1
                ? "There is 1 care item ready in your current Jungle window."
                : "There are \(count) care items ready in your current Jungle window.",
            action: .openJungleDue,
            actionTitle: "See Plant Care"
        )
    }

    private func matchingPlants(query: String, plants: [Plant]) -> [Plant] {
        let needle = normalize(query)
        let exact = plants.filter { plant in
            normalize(plant.displayName) == needle
                || normalize(plant.name) == needle
                || plant.nickname.map(normalize) == needle
        }
        if !exact.isEmpty { return exact }

        return plants.filter { plant in
            normalize(plant.displayName).contains(needle)
                || normalize(plant.name).contains(needle)
                || (plant.nickname.map(normalize).map { $0.contains(needle) } ?? false)
        }
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func careDescription(_ type: CareType) -> String {
        switch type {
        case .water: "watering"
        case .fertilize: "fertilizing"
        case .mist: "misting"
        case .rotate: "rotation"
        case .cleanLeaves: "leaf cleaning"
        case .prune: "pruning"
        case .repot: "repotting"
        case .propagate: "propagation"
        case .pestTreatment: "pest treatment"
        case .healthInspection: "a health check"
        case .custom: "care"
        }
    }
}

/// Native speech capture for Tell Sunnie. Speech recognition is optional: text
/// input remains complete when permission is declined or recognition is absent.
@MainActor
@Observable
final class TellSunnieSpeechController {
    private(set) var isListening = false
    private(set) var statusText: String?
    var transcript = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var hasInstalledTap = false

    func toggle(capabilities: CapabilitySnapshot) async {
        if isListening {
            stop()
        } else {
            guard capabilities[.microphone] != .denied,
                  capabilities[.microphone] != .restricted,
                  capabilities[.microphone] != .unavailable,
                  capabilities[.speechRecognition] != .denied,
                  capabilities[.speechRecognition] != .restricted,
                  capabilities[.speechRecognition] != .unavailable else {
                statusText = "Voice input isn’t available with the current access settings. You can still type here."
                return
            }
            await start()
        }
    }

    func start() async {
        guard await requestPermissions() else {
            statusText = "Voice input is unavailable without microphone and speech-recognition access. You can still type here."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            statusText = "Voice recognition isn’t available right now. You can still type here."
            return
        }

        stop()
        transcript = ""
        statusText = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer the device-local recognizer whenever this language/device
        // supports it. Text remains the complete fallback if recognition is not
        // available at all.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledTap = true

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            stop()
            statusText = "Voice input couldn’t start just now. You can still type here."
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

struct TellSunnieScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var model: TellSunnieModel?
    @State private var speech = TellSunnieSpeechController()
    @State private var input = ""

    init(initialText: String = "") {
        _input = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.m) {
                    SunnieCard {
                        SectionHeader(
                            title: "Tell Sunnie",
                            subtitle: "Say it normally. Sunnie Days will work out where it belongs."
                        )

                        Text("Try “Watered Fern,” “add my charger to packing,” or “what do I still have for my flight?”")
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let response = model?.response {
                        responseCard(response)
                    }

                    SunnieCard {
                        TextField(
                            "Tell Sunnie something…",
                            text: $input,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...6)
                        .submitLabel(.send)
                        .onSubmit { submit() }

                        HStack(spacing: Space.s) {
                            Button {
                                Task {
                                    let capabilities = await dependencies.capabilityBroker.snapshot()
                                    await speech.toggle(capabilities: capabilities)
                                }
                            } label: {
                                Label(
                                    speech.isListening ? "Stop listening" : "Speak",
                                    systemImage: speech.isListening ? "stop.circle" : "mic"
                                )
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button {
                                submit()
                            } label: {
                                if model?.isWorking == true {
                                    ProgressView()
                                } else {
                                    Label("Send", systemImage: "arrow.up.circle.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || model?.isWorking == true)
                        }

                        if let status = speech.statusText {
                            Text(status)
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle("Tell Sunnie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if model == nil {
                    model = TellSunnieModel(dependencies: dependencies, appState: appState)
                }
                await appState.refreshCurrentContext()
            }
            .onChange(of: speech.transcript) { _, newValue in
                if !newValue.isEmpty { input = newValue }
            }
            .onDisappear { speech.stop() }
        }
    }

    private func responseCard(_ response: TellSunnieResponse) -> some View {
        SunnieCard {
            Text(response.text)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let action = response.action,
               let route = action.appRoute,
               let title = response.actionTitle {
                Button(title) {
                    dismiss()
                    router.handle(route)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func submit() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        speech.stop()

        Task {
            guard let model else { return }
            let response = await model.submit(text)
            input = ""
            if response.openImmediately,
               let route = response.action?.appRoute {
                dismiss()
                router.handle(route)
            }
        }
    }
}
