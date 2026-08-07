import SwiftUI
import SunnieShared

/// Today on the wrist (§6): an affirmation, the next task, and what is due.
///
/// Everything shown here was resolved on the phone. The Watch picks no message
/// and computes no due date — it renders a snapshot.
struct WatchTodayScreen: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.presentationName)
                    .font(.headline)

                if let greeting = model.context?.sunnieGreeting {
                    Text(greeting)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let affirmation = model.affirmation {
                    Text(affirmation)
                        .font(.footnote)
                }

                if let next = model.features?.nextTaskDescription {
                    Label(next, systemImage: "leaf")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let travel = model.travel,
                   let days = travel.daysUntilDeparture(now: Date(), calendar: .current) {
                    Label("\(days) days", systemImage: "airplane")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.context == nil {
                    Text("Open Sunnie Days on your iPhone to see what's waiting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if model.dueTasks.isEmpty {
                    Text("Nothing waiting. Your jungle is looking cared for.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(model.dueTasks.count) may be ready for a little attention.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Today")
    }
}

struct WatchPlantsScreen: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            if model.dueTasks.isEmpty {
                Text("Nothing waiting right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.dueTasks) { task in
                    WatchTaskRow(task: task)
                }
            }
        }
        .navigationTitle("Plants")
    }
}

struct WatchTaskRow: View {
    @Environment(WatchModel.self) private var model

    let task: WatchDueTask

    var body: some View {
        let isDone = model.isCompleted(task)

        Button {
            guard !isDone else { return }
            model.completeCare(task)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.plantDisplayName)
                        .font(.body)
                    Text(careTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : "drop")
                    .foregroundStyle(isDone ? .green : .secondary)
            }
        }
        .disabled(isDone)
        // The action is confirmed on the wrist immediately. If the phone is out
        // of range the transfer is queued, so there is nothing for the user to
        // wait for or retry.
        .accessibilityLabel(
            isDone
                ? Text("\(task.plantDisplayName), done")
                : Text("Mark \(task.plantDisplayName) \(careTitle.lowercased())")
        )
    }

    /// Falls back to a neutral word rather than guessing when the phone sends a
    /// care type this build does not know.
    private var careTitle: String {
        guard let careType = task.careType else { return "Care" }
        switch careType {
        case .water: return "Water"
        case .fertilize: return "Fertilize"
        case .mist: return "Mist"
        default: return "Care"
        }
    }
}
