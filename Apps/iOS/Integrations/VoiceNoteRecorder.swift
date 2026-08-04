import Foundation
import Observation
import SunnieShared
#if canImport(AVFAudio)
import AVFAudio
#endif

/// Records short voice notes for the journal and check-ins.
///
/// Recordings go to a temporary file and are handed to the media repository as
/// bytes, so nothing outside Persistence ever holds a path. The temporary file is
/// removed as soon as the data is read, whether or not the caller keeps it.
///
/// Voice-note content is never logged, transcribed, or analysed. It is bytes the
/// user recorded, stored on their device (WELLNESS_JOURNAL_AND_CALM.md §13).
@MainActor
@Observable
final class VoiceNoteRecorder {

    enum State: Equatable {
        case idle
        case denied
        case recording
        case finished(duration: TimeInterval)
        /// Something went wrong. Carries copy that is already user-safe.
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0

    /// Long enough for a thought, short enough not to fill the disk unnoticed.
    static let maximumDuration: TimeInterval = 5 * 60

    private let log = SunnieLog(category: .persistence)
    private var tickTask: Task<Void, Never>?

    #if canImport(AVFAudio)
    private var recorder: AVAudioRecorder?
    #endif
    private var fileURL: URL?

    var isRecording: Bool { state == .recording }

    /// Asks for microphone access.
    ///
    /// Only ever called from an explicit tap on the record button — never at
    /// launch and never speculatively.
    func requestPermission() async -> Bool {
        #if canImport(AVFAudio)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        false
        #endif
    }

    func start() async {
        #if canImport(AVFAudio)
        guard await requestPermission() else {
            state = .denied
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            // `.playAndRecord` for the duration of the recording only; the
            // ambient category is restored on stop so Sunnie's audio goes back to
            // never interrupting anything.
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .spokenAudio, options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: Self.maximumDuration)

            self.recorder = recorder
            self.fileURL = url
            self.elapsed = 0
            state = .recording
            startTicking()
        } catch {
            log.error("Could not start a voice recording.")
            state = .failed(String(
                localized: "voiceNote.error.start",
                defaultValue: "I couldn't start recording just now. Nothing else has changed.",
                comment: "Shown when a voice recording cannot start"
            ))
        }
        #else
        state = .denied
        #endif
    }

    /// Stops and returns the recorded bytes.
    ///
    /// Returns nil if nothing was recorded. The temporary file is always removed,
    /// so an abandoned recording leaves nothing behind.
    @discardableResult
    func stop() async -> (data: Data, duration: TimeInterval)? {
        tickTask?.cancel()
        tickTask = nil

        #if canImport(AVFAudio)
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        #endif

        defer {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            fileURL = nil
        }

        guard let fileURL, let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            state = .idle
            return nil
        }

        let duration = elapsed
        state = .finished(duration: duration)
        return (data, duration)
    }

    /// Throws the recording away without keeping it.
    func cancel() async {
        _ = await stop()
        state = .idle
        elapsed = 0
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.elapsed += 0.1
                if self.elapsed >= Self.maximumDuration {
                    _ = await self.stop()
                    return
                }
            }
        }
    }
}

/// Attaches captured media to a record.
///
/// Sits between the capture surfaces and the media repository so no screen ever
/// talks to storage directly, and so the token-generation rule lives in one place.
struct AttachMedia: Sendable {

    private let repository: any MediaRepository
    private let clock: any SunnieClock

    init(repository: any MediaRepository, clock: any SunnieClock) {
        self.repository = repository
        self.clock = clock
    }

    @discardableResult
    func callAsFunction(
        data: Data,
        kind: MediaKind,
        owner: MediaOwner,
        duration: TimeInterval? = nil
    ) async throws -> MediaAttachment {
        let store = MediaFileStore()
        let attachment = MediaAttachment(
            owner: owner,
            kind: kind,
            localToken: store.makeToken(for: kind),
            duration: duration,
            createdAt: clock.now
        )
        return try await repository.save(attachment, data: data)
    }

    func attachments(for owner: MediaOwner) async throws -> [MediaAttachment] {
        try await repository.attachments(for: owner)
    }

    func data(for attachmentID: UUID) async throws -> Data? {
        try await repository.data(for: attachmentID)
    }

    func remove(attachmentID: UUID) async throws {
        try await repository.delete(attachmentID: attachmentID)
    }
}
