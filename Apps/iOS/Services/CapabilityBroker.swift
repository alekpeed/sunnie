import AVFoundation
import BackgroundTasks
import Foundation
import Photos
import Speech
import UIKit
import UserNotifications
import SunnieShared

#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The only place that translates native authorization APIs into Sunnie Days'
/// stable capability vocabulary. Reading never prompts; features still own the
/// just-in-time request that follows a user action.
final class CapabilityBroker: CapabilityProviding, @unchecked Sendable {
    func snapshot() async -> CapabilitySnapshot {
        var states: [SunnieCapability: CapabilityState] = [:]
        states[.microphone] = Self.microphoneState
        states[.speechRecognition] = Self.speechState
        states[.photoLibrary] = Self.photoState
        states[.camera] = Self.cameraState
        states[.notifications] = await Self.notificationState
        states[.health] = Self.healthState
        states[.location] = .notRequested
        states[.weather] = .authorized
        states[.watchConnectivity] = Self.watchState
        states[.backgroundRefresh] = await Self.backgroundState
        states[.widgets] = Self.appGroupState
        states[.foundationModels] = .unavailable
        return CapabilitySnapshot(generatedAt: Date(), states: states)
    }

    private static var microphoneState: CapabilityState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .authorized
        case .denied: .denied
        case .undetermined: .notRequested
        @unknown default: .unavailable
        }
    }

    private static var speechState: CapabilityState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notRequested
        @unknown default: .unavailable
        }
    }

    private static var photoState: CapabilityState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notRequested
        @unknown default: .unavailable
        }
    }

    private static var cameraState: CapabilityState {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notRequested
        @unknown default: .unavailable
        }
    }

    private static var notificationState: CapabilityState {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .authorized
            case .denied: .denied
            case .notDetermined: .notRequested
            @unknown default: .unavailable
            }
        }
    }

    private static var healthState: CapabilityState {
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        return HKHealthStore.isHealthDataAvailable() ? .notRequested : .unavailable
        #else
        return .unavailable
        #endif
    }

    private static var watchState: CapabilityState {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return .unavailable }
        return WCSession.default.isPaired ? .authorized : .unavailable
        #else
        return .unavailable
        #endif
    }

    @MainActor private static var backgroundState: CapabilityState {
        get async {
            switch UIApplication.shared.backgroundRefreshStatus {
            case .available: .authorized
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .unavailable
            }
        }
    }

    private static var appGroupState: CapabilityState {
        UserDefaults(suiteName: "group.com.sunniedays.shared") == nil ? .unavailable : .authorized
    }
}
