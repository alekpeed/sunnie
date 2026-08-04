import Foundation
import SunnieShared
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Local notification scheduling and delivery.
///
/// Permission is never requested at launch. The app is fully usable with
/// notifications denied, and asking before the user has seen why would be the
/// kind of pressure the tone rules forbid — the request lives in Settings, behind
/// a button they choose to press.
///
/// Copy arrives already composed. This service never selects or assembles what
/// Sunnie says; it schedules text someone else resolved from the content pack.
final class NotificationService: NSObject, NotificationScheduling, @unchecked Sendable {

    private let log = SunnieLog(category: .notifications)

    /// Called when the user taps a notification. Set by the composition root so
    /// a tap resolves into the same typed route system as a deep link or a
    /// widget (INFORMATION_ARCHITECTURE.md §13).
    var onRouteRequested: (@Sendable (String) -> Void)?
    /// Called when the user acts on a notification without opening the app.
    var onAction: (@Sendable (DeliveredNotificationAction) -> Void)?

    /// Action identifiers. Every category offers "later" and "skip today" so a
    /// reminder can always be dismissed kindly rather than only ignored
    /// (NOTIFICATIONS_AND_REMINDERS.md §6).
    enum Action {
        static let complete = "sunnie.action.complete"
        static let snooze = "sunnie.action.snooze"
        static let skipToday = "sunnie.action.skipToday"
        static let category = "sunnie.category.reminder"
    }

    func registerCategories() {
        #if canImport(UserNotifications)
        let complete = UNNotificationAction(
            identifier: Action.complete,
            title: String(
                localized: "notification.action.complete",
                defaultValue: "Done",
                comment: "Marks the reminded task complete from the notification"
            ),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Action.snooze,
            title: String(
                localized: "notification.action.snooze",
                defaultValue: "Later",
                comment: "Postpones a reminder"
            ),
            options: []
        )
        let skip = UNNotificationAction(
            identifier: Action.skipToday,
            title: String(
                localized: "notification.action.skipToday",
                defaultValue: "Not today",
                comment: "Skips a reminder for the rest of the day"
            ),
            options: []
        )

        let category = UNNotificationCategory(
            identifier: Action.category,
            actions: [complete, snooze, skip],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        #endif
    }

    func authorizationStatus() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
        #else
        return .notDetermined
        #endif
    }

    func requestAuthorization() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            log.debug("Notification authorization could not be requested.")
            return .denied
        }
        #else
        return .denied
        #endif
    }

    func schedule(_ reminder: ScheduledReminderRequest) async throws {
        #if canImport(UserNotifications)
        guard await authorizationStatus() == .authorized else {
            throw DomainError.permissionDenied(capability: "notifications")
        }

        let interval = reminder.fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.categoryIdentifier = Action.category
        // Thread identifier collapses related reminders instead of stacking five
        // separate plant notifications in Notification Centre.
        content.threadIdentifier = reminder.threadIdentifier
        var userInfo: [String: String] = [
            NotificationPayloadKeys.route: reminder.route,
            NotificationPayloadKeys.reminderID: reminder.id.uuidString,
            NotificationPayloadKeys.messageID: reminder.messageID.rawValue
        ]
        for (key, value) in reminder.actionPayload {
            userInfo[NotificationPayloadKeys.actionPrefix + key] = value
        }
        content.userInfo = userInfo
        // Silent during quiet hours rather than suppressed entirely: the task is
        // still there, it just doesn't make a sound.
        content.sound = reminder.respectsQuietHours ? nil : .default
        // No badge. A number on the icon reads as debt, which is exactly the
        // framing the tone rules rule out.
        content.badge = nil

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval, repeats: false
            )
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            throw DomainError.persistenceFailed(operation: "scheduleReminder")
        }
        #else
        throw DomainError.permissionDenied(capability: "notifications")
        #endif
    }

    func cancel(reminderID: UUID) async {
        #if canImport(UserNotifications)
        let identifier = reminderID.uuidString
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        // Also clear it if it already fired — a delivered notification for a
        // finished task is the same nuisance as a pending one.
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        #endif
    }

    #if canImport(UserNotifications)
    private static func map(
        _ status: UNAuthorizationStatus
    ) -> NotificationAuthorization {
        switch status {
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
    #endif
}

#if canImport(UserNotifications)
extension NotificationService: UNUserNotificationCenterDelegate {

    /// A reminder arriving while the app is open is shown as a quiet banner
    /// rather than suppressed — the user may be looking at a different tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard
            let reminderID = (info[NotificationPayloadKeys.reminderID] as? String)
                .flatMap(UUID.init(uuidString:))
        else { return }

        // Strip the prefix back off, so the handler sees the keys the scheduler
        // wrote rather than their transport form.
        var payload: [String: String] = [:]
        for case let (key as String, value as String) in info
        where key.hasPrefix(NotificationPayloadKeys.actionPrefix) {
            payload[String(key.dropFirst(NotificationPayloadKeys.actionPrefix.count))] = value
        }

        func deliver(_ userResponse: ReminderResponse) {
            onAction?(DeliveredNotificationAction(
                reminderID: reminderID, response: userResponse, payload: payload
            ))
        }

        switch response.actionIdentifier {
        case Action.complete: deliver(.completed)
        case Action.snooze: deliver(.snoozed)
        case Action.skipToday: deliver(.skippedForToday)
        case UNNotificationDismissActionIdentifier: deliver(.dismissed)
        default:
            // Tapped the notification itself: record it as opened and route.
            deliver(.opened)
            if let route = info[NotificationPayloadKeys.route] as? String {
                onRouteRequested?(route)
            }
        }
    }
}
#endif
