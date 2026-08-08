import SwiftUI
import SunnieShared
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Photo and voice-note attachment, shared by the journal editor and the
/// check-in sheet.
///
/// **Placeholder presentation.** The behaviour is real: photos come from the
/// system picker (which needs no library permission, because it runs out of
/// process and hands back only what the user chose), and voice notes record
/// through `VoiceNoteRecorder`.
///
/// Attaching is always optional and always removable. Nothing here nags for a
/// photo or treats an entry without one as incomplete.
struct AttachmentsSection: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let owner: MediaOwner
    /// Called with the current attachment count whenever it changes, and once
    /// after the initial load. The count matters to hosts that treat "has an
    /// attachment" as content in its own right — a check-in with only a voice
    /// note is a real entry.
    var onChange: (Int) -> Void = { _ in }

    @State private var attachments: [MediaAttachment] = []
    @State private var recorder = VoiceNoteRecorder()
    @State private var errorMessage: String?

    #if canImport(PhotosUI)
    @State private var photoSelection: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    attachmentRow(attachment)
                }
            }

            HStack(spacing: Space.s) {
                photoButton
                voiceButton
            }

            if recorder.isRecording {
                recordingIndicator
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .task { await reload() }
    }

    // MARK: - Controls

    @ViewBuilder
    private var photoButton: some View {
        #if canImport(PhotosUI)
        PhotosPicker(selection: $photoSelection, matching: .images) {
            Label(
                String(
                    localized: "attachment.addPhoto",
                    defaultValue: "Photo",
                    comment: "Attaches a photo"
                ),
                systemImage: "photo"
            )
            .font(SunnieFont.secondary)
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await attachPhoto(item) }
        }
        #endif
    }

    private var voiceButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            Label(
                recorder.isRecording
                    ? String(
                        localized: "attachment.stopRecording",
                        defaultValue: "Stop",
                        comment: "Stops recording a voice note"
                    )
                    : String(
                        localized: "attachment.addVoiceNote",
                        defaultValue: "Voice note",
                        comment: "Records a voice note"
                    ),
                systemImage: recorder.isRecording ? "stop.circle" : "mic"
            )
            .font(SunnieFont.secondary)
        }
        .foregroundStyle(recorder.isRecording ? theme.color.attention : theme.color.accentCalm)
    }

    private var recordingIndicator: some View {
        HStack(spacing: Space.xs) {
            // Text, not just a pulsing dot — recording state must be readable
            // without relying on motion or colour.
            Text(
                "attachment.recording \(Int(recorder.elapsed))",
                bundle: .main,
                comment: "Shows elapsed recording seconds"
            )
            .font(SunnieFont.numeric)
            .foregroundStyle(theme.color.attention)

            Spacer()

            Button(String(
                localized: "common.cancel",
                defaultValue: "Cancel",
                comment: "Discards the recording"
            )) {
                Task {
                    await recorder.cancel()
                }
            }
            .font(SunnieFont.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func attachmentRow(_ attachment: MediaAttachment) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: attachment.kind == .photo ? "photo" : "waveform")
                .foregroundStyle(theme.color.accentCalm)
                .accessibilityHidden(true)

            Text(label(for: attachment))
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textPrimary)

            Spacer()

            Button {
                Task { await remove(attachment) }
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(theme.color.textSecondary)
            }
            .accessibilityLabel(Text(
                "attachment.remove",
                bundle: .main,
                comment: "Removes an attachment"
            ))
        }
        .accessibilityElement(children: .combine)
    }

    private func label(for attachment: MediaAttachment) -> String {
        switch attachment.kind {
        case .photo:
            String(localized: "attachment.photo", defaultValue: "Photo", comment: "A photo attachment")
        case .voiceNote:
            String(
                localized: "attachment.voiceNote",
                defaultValue: "Voice note, \(Int(attachment.duration ?? 0))s",
                comment: "A voice note attachment with its length"
            )
        }
    }

    // MARK: - Actions

    private func reload() async {
        attachments = (try? await dependencies.attachMedia.attachments(for: owner)) ?? []
        onChange(attachments.count)
    }

    #if canImport(PhotosUI)
    private func attachPhoto(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = String(
                localized: "attachment.error.photo",
                defaultValue: "I couldn't read that photo. Nothing else has changed.",
                comment: "Shown when a photo cannot be attached"
            )
            return
        }
        await store(data: data, kind: .photo, duration: nil)
    }
    #endif

    private func toggleRecording() async {
        if recorder.isRecording {
            guard let result = await recorder.stop() else { return }
            await store(data: result.data, kind: .voiceNote, duration: result.duration)
        } else {
            errorMessage = nil
            await recorder.start()
            if recorder.state == .denied {
                errorMessage = String(
                    localized: "attachment.error.microphone",
                    defaultValue: "Recording needs microphone access, which you can turn on in Settings. Everything else works without it.",
                    comment: "Shown when microphone permission is denied"
                )
            }
        }
    }

    private func store(data: Data, kind: MediaKind, duration: TimeInterval?) async {
        do {
            _ = try await dependencies.attachMedia(
                data: data, kind: kind, owner: owner, duration: duration
            )
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = String(
                localized: "attachment.error.save",
                defaultValue: "That didn't attach just now. Everything you've written is still here.",
                comment: "Shown when an attachment cannot be saved"
            )
        }
    }

    private func remove(_ attachment: MediaAttachment) async {
        try? await dependencies.attachMedia.remove(attachmentID: attachment.id)
        await reload()
    }
}
