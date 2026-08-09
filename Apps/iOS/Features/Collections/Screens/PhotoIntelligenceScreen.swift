import SwiftUI
import PhotosUI
import Vision
import UIKit

/// Advisory, on-device photo interpretation. The selected image is not written
/// anywhere by this screen; it only proposes which existing Sunnie Days feature
/// is the right place to continue.
struct PhotoIntelligenceScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let onOpenRoute: (AppRoute) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var result: PhotoSuggestion?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var analysisGeneration = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                SunnieCard {
                    SectionHeader(
                        title: "Photo Intelligence",
                        subtitle: "Choose an image. Classification runs on this device."
                    )

                    Text("Sunnie will suggest where the photo belongs. A suggestion is not saved and never changes a record by itself.")
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Selected photo")
                }

                if isAnalyzing {
                    SunnieCard {
                        ProgressView()
                        Text("Looking at the photo…")
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }

                if let result {
                    suggestionCard(result)
                }

                if let errorMessage {
                    SunnieCard {
                        Label("I couldn't classify that image", systemImage: "exclamationmark.triangle")
                            .font(SunnieFont.cardTitle)
                            .foregroundStyle(theme.color.textPrimary)
                        Text(errorMessage)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle("Photo Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            let generation = UUID()
            analysisGeneration = generation
            Task { await loadAndAnalyze(item, generation: generation) }
        }
    }

    @ViewBuilder
    private func suggestionCard(_ suggestion: PhotoSuggestion) -> some View {
        SunnieCard {
            Label(suggestion.title, systemImage: suggestion.symbol)
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)

            Text(suggestion.detail)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textSecondary)

            if !suggestion.labels.isEmpty {
                Text("Vision saw: \(suggestion.labels.prefix(3).joined(separator: ", "))")
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            if let route = suggestion.route {
                SunniePrimaryButton(title: suggestion.actionTitle) {
                    onOpenRoute(route)
                }
            }
        }
    }

    @MainActor
    private func loadAndAnalyze(_ item: PhotosPickerItem, generation: UUID) async {
        guard generation == analysisGeneration else { return }
        isAnalyzing = true
        errorMessage = nil
        result = nil

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                throw PhotoIntelligenceError.unreadableImage
            }

            guard generation == analysisGeneration else { return }
            let suggestion = try classify(image)
            guard generation == analysisGeneration else { return }

            selectedImage = image
            result = suggestion
            isAnalyzing = false
        } catch {
            guard generation == analysisGeneration else { return }
            errorMessage = error.localizedDescription
            isAnalyzing = false
        }
    }

    private func classify(_ image: UIImage) throws -> PhotoSuggestion {
        guard let cgImage = image.cgImage else {
            throw PhotoIntelligenceError.unreadableImage
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let labels = (request.results ?? [])
            .filter { $0.confidence >= 0.05 }
            .prefix(8)
            .map(\.identifier)

        return PhotoSuggestion.resolve(
            labels: labels,
            hasActiveTrip: appState.currentContext.flightMode != nil
        )
    }
}

private enum PhotoIntelligenceError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The selected item could not be read as an image."
        }
    }
}

private struct PhotoSuggestion {
    let title: String
    let detail: String
    let symbol: String
    let actionTitle: String
    let route: AppRoute?
    let labels: [String]

    static func resolve(labels: [String], hasActiveTrip: Bool) -> PhotoSuggestion {
        if matches(labels, aliases: [
            "plant", "flower", "leaf", "foliage", "houseplant", "tree", "succulent", "cactus"
        ]) {
            return PhotoSuggestion(
                title: "This looks plant-related",
                detail: "Open Jungle to choose the plant or growth entry this image belongs with.",
                symbol: "leaf.fill",
                actionTitle: "Open Jungle",
                route: .jungle,
                labels: labels
            )
        }

        if matches(labels, aliases: [
            "food", "dish", "meal", "plate", "dessert", "bread", "fruit", "vegetable", "restaurant"
        ]) {
            return PhotoSuggestion(
                title: "This looks food-related",
                detail: "Open Meals to connect it with a recipe, meal plan, or food memory.",
                symbol: "fork.knife",
                actionTitle: "Open Meals",
                route: .meals,
                labels: labels
            )
        }

        if matches(labels, aliases: [
            "receipt", "document", "paper", "ticket", "passport", "booklet", "menu", "text"
        ]) {
            return PhotoSuggestion(
                title: "This may be a document",
                detail: hasActiveTrip
                    ? "Because a work trip is active, Travel is the best place to decide whether this belongs with the trip."
                    : "Travel is the best place to decide whether this belongs with a trip or saved place.",
                symbol: "doc.text.fill",
                actionTitle: "Open Travel",
                route: .travel,
                labels: labels
            )
        }

        if matches(labels, aliases: [
            "luggage", "suitcase", "bag", "backpack", "clothing", "shoe", "electronics", "charger"
        ]), hasActiveTrip {
            return PhotoSuggestion(
                title: "This may belong with packing",
                detail: "Flight Mode is active, so the current trip is the strongest context for this image.",
                symbol: "suitcase.fill",
                actionTitle: "Open Travel",
                route: .travel,
                labels: labels
            )
        }

        if matches(labels, aliases: [
            "building", "architecture", "landmark", "city", "street", "bridge", "mountain", "beach", "landscape"
        ]) || hasActiveTrip {
            return PhotoSuggestion(
                title: "This looks like a place or travel memory",
                detail: "Open Travel to attach it to the appropriate trip, place, or memory after you confirm the match.",
                symbol: "map.fill",
                actionTitle: "Open Travel",
                route: .travel,
                labels: labels
            )
        }

        return PhotoSuggestion(
            title: "This looks like a personal memory",
            detail: "Sunnie doesn't have a high-confidence feature match. Keep the image unchanged until you choose where it belongs.",
            symbol: "photo.fill",
            actionTitle: "Back to Sunnie's World",
            route: nil,
            labels: labels
        )
    }

    /// Matches aliases as token sequences rather than arbitrary substrings.
    /// This keeps labels such as "street" from accidentally matching "tree".
    private static func matches(_ labels: [String], aliases: [String]) -> Bool {
        let labelTokens = labels.map(tokens)
        let aliasTokens = aliases.map(tokens)
        return labelTokens.contains { label in
            aliasTokens.contains { alias in containsSequence(label, alias) }
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        if needle.count == 1 { return haystack.contains(needle[0]) }

        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}
