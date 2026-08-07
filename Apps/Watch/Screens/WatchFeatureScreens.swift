import SwiftUI
import WatchKit
import SunnieShared

/// Check In, Calm, and Travel on the wrist
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §6).
///
/// All three follow the same rule as the plants screen: the wrist confirms the
/// tap and the transfer is queued, so nothing here waits on the phone or asks
/// the user to retry. A check-in made on a plane arrives when the phone is next
/// reachable.
///
/// The Watch computes nothing it could get wrong. It has no content pack, no
/// schedule maths, and no message selection — everything it shows arrived
/// already resolved.

// MARK: - Check In

struct WatchCheckInScreen: View {
    @Environment(WatchModel.self) private var model

    @State private var mood: WellnessScaleValue = .neutral
    @State private var energy: WellnessScaleValue = .neutral
    @State private var didSave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if didSave || model.hasCheckedInToday {
                    // A quiet note, not a prompt. Having checked in already is
                    // not a reason to be told to do it again.
                    Label("Noted for today", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                scale("How are things?", value: $mood)
                if model.offersEnergy {
                    scale("Energy", value: $energy)
                }

                Button {
                    model.recordCheckIn(mood: mood, energy: model.offersEnergy ? energy : nil)
                    didSave = true
                } label: {
                    Text(didSave ? "Saved" : "Save")
                        .frame(maxWidth: .infinity)
                }
                .disabled(didSave)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Check in")
    }

    /// A 1–5 picker with no adjectives on the numbers.
    ///
    /// The phone labels each point per dimension, because "low" means opposite
    /// things for energy and stress. The wrist has no room for that, so it shows
    /// the number and lets the accessibility label carry the meaning.
    private func scale(_ title: String, value: Binding<WellnessScaleValue>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Picker(title, selection: value) {
                ForEach(WellnessScaleValue.allCases, id: \.self) { option in
                    Text("\(option.rawValue)").tag(option)
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityLabel(Text("\(title), \(value.wrappedValue.rawValue) of 5"))
        }
    }
}

// MARK: - Calm

struct WatchCalmScreen: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            if model.practices.isEmpty {
                Text("Open Sunnie Days on your iPhone to bring your practices across.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.practices) { practice in
                    NavigationLink(practice.displayName) {
                        WatchBreathingScreen(practice: practice)
                    }
                }
            }
        }
        .navigationTitle("Calm")
    }
}

/// The breathing pacer.
///
/// Haptics rather than sound, and haptics that can be turned off (§6). A pacer
/// that required audio would be useless in a meeting, which is one of the places
/// someone most wants one.
struct WatchBreathingScreen: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let practice: WatchFeatureContext.CalmPanel.Practice

    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var lastPhase: BreathPhase?
    @State private var didFinish = false

    /// One second, which is as fine as a breathing pacer needs and gentler on
    /// the battery than a display-rate timer would be.
    private static let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum BreathPhase: String {
        case inhale = "Breathe in"
        case holdIn = "Hold"
        case exhale = "Breathe out"
        case holdOut = "Rest"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(phase?.rawValue ?? "Done")
                .font(.headline)
                .contentTransition(.opacity)

            Text(remainingText)
                .font(.system(.title3, design: .rounded))
                .monospacedDigit()

            Button(didFinish ? "Done" : "Finish") { finish(.endedEarly) }
                .buttonStyle(.bordered)
        }
        .navigationTitle(practice.displayName)
        .onReceive(Self.ticker) { _ in tick() }
        .onDisappear {
            // Leaving is a legitimate way to end a practice. It is recorded as
            // ended early, which the phone treats exactly as neutrally as
            // finishing (WELLNESS_JOURNAL_AND_CALM.md).
            finish(.endedEarly)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(phase?.rawValue ?? "Practice finished"))
    }

    /// Where in the cycle we are.
    ///
    /// Computed from elapsed time rather than advanced by a state machine, so a
    /// dropped tick — the wrist lowering, the app being suspended — resyncs on
    /// the next one instead of drifting for the rest of the session.
    private var phase: BreathPhase? {
        guard !didFinish, practice.cycleDuration > 0 else { return nil }
        var position = elapsed.truncatingRemainder(dividingBy: practice.cycleDuration)

        if position < practice.inhaleSeconds { return .inhale }
        position -= practice.inhaleSeconds

        if position < practice.holdAfterInhaleSeconds { return .holdIn }
        position -= practice.holdAfterInhaleSeconds

        if position < practice.exhaleSeconds { return .exhale }
        return .holdOut
    }

    private var remainingText: String {
        let remaining = max(0, practice.defaultDuration - elapsed)
        return "\(Int(remaining / 60)):\(String(format: "%02d", Int(remaining) % 60))"
    }

    private func tick() {
        guard !didFinish else { return }
        elapsed += 1

        if let phase, phase != lastPhase {
            lastPhase = phase
            if model.usesHapticPacing {
                WKInterfaceDevice.current().play(phase == .exhale ? .directionDown : .directionUp)
            }
        }

        if elapsed >= practice.defaultDuration {
            finish(.completed)
        }
    }

    private func finish(_ completion: WellnessSessionCompletion) {
        guard !didFinish else { return }
        didFinish = true
        model.recordSession(
            practice: practice,
            startedAt: startedAt,
            endedAt: Date(),
            completion: completion
        )
    }
}

// MARK: - Travel

struct WatchTravelScreen: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            if let travel = model.travel {
                Section {
                    Text(travel.tripTitle).font(.headline)
                    if let days = travel.daysUntilDeparture(now: Date(), calendar: .current) {
                        Label("\(days) days", systemImage: "airplane.departure")
                            .font(.footnote)
                    }
                }

                clocksSection(travel)

                if !travel.checklistItems.isEmpty {
                    Section("Still to do") {
                        ForEach(travel.checklistItems) { item in
                            checklistRow(item)
                        }
                    }
                }

                Section {
                    // Hydration on the wrist, because the wrist is where someone
                    // is when they actually drink something on a plane.
                    ForEach(HydrationLog.quickAmounts, id: \.self) { amount in
                        Button("\(amount) ml") { model.logWater(millilitres: amount) }
                    }
                } header: {
                    Text("Water")
                }
            } else {
                Text("No trip on right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Travel")
    }

    /// Home and destination, side by side.
    ///
    /// The single most useful thing on a wrist while away, and the one thing a
    /// watch face cannot show — it has exactly one time zone.
    @ViewBuilder
    private func clocksSection(_ travel: WatchFeatureContext.TravelPanel) -> some View {
        if let destinationID = travel.destinationTimeZoneID,
           let destination = TimeZone(identifier: destinationID),
           let home = TimeZone(identifier: travel.homeTimeZoneID) {
            Section {
                clockRow("There", zone: destination)
                clockRow("Home", zone: home)
            }
        }
    }

    private func clockRow(_ title: String, zone: TimeZone) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            // The zone is passed to the format style rather than set as a
            // symbol, which is the difference between showing the right time and
            // showing the local time beside the right label.
            Text(
                Date().formatted(
                    Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)
                )
            )
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func checklistRow(
        _ item: WatchFeatureContext.TravelPanel.ChecklistEntry
    ) -> some View {
        let isTicked = model.isTicked(item)

        return Button {
            model.tickChecklistItem(item)
        } label: {
            HStack {
                Text(item.title).font(.body)
                Spacer()
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isTicked ? .green : .secondary)
            }
        }
        .disabled(isTicked)
        .accessibilityLabel(
            isTicked ? Text("\(item.title), done") : Text("Mark \(item.title) done")
        )
    }
}
