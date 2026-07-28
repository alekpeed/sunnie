import SwiftUI
import SunnieShared

/// Short sheet for logging one care action.
///
/// **Placeholder presentation.** The behaviour is real: the timestamp can be
/// backdated so the user records what they actually did rather than when they
/// happened to open the app, and the note is optional. Nothing here is required
/// beyond picking the care type.
struct QuickCareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let careTypes: [CareType]
    let onLog: (CareType, Date, String?) -> Void

    @State private var selectedCareType: CareType
    @State private var performedAt = Date()
    @State private var note = ""

    init(careTypes: [CareType], onLog: @escaping (CareType, Date, String?) -> Void) {
        self.careTypes = careTypes
        self.onLog = onLog
        _selectedCareType = State(initialValue: careTypes.first ?? .water)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        String(
                            localized: "quickCare.type",
                            defaultValue: "What did you do?",
                            comment: "Care type picker label"
                        ),
                        selection: $selectedCareType
                    ) {
                        ForEach(careTypes, id: \.storageKey) { careType in
                            Label(
                                CareTypeCopy.title(careType),
                                systemImage: CareTypeCopy.symbolName(careType)
                            )
                            .tag(careType)
                        }
                    }
                }

                Section {
                    DatePicker(
                        String(
                            localized: "quickCare.when",
                            defaultValue: "When",
                            comment: "Timestamp picker label"
                        ),
                        selection: $performedAt,
                        // Backdating is allowed; future timestamps are not,
                        // because they would poison the next-due calculation.
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text(
                        "quickCare.when.footer",
                        bundle: .main,
                        comment: "Explains that the time can be adjusted"
                    )
                }

                Section {
                    TextField(
                        String(
                            localized: "quickCare.note",
                            defaultValue: "Anything to remember? (optional)",
                            comment: "Optional note field"
                        ),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                }
            }
            .navigationTitle(Text("quickCare.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel button"
                    )) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "quickCare.save",
                        defaultValue: "Save",
                        comment: "Saves the care record"
                    )) {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onLog(selectedCareType, performedAt, trimmed.isEmpty ? nil : trimmed)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
