import UserNotifications

private let categoryStreamActive = "STREAM_ACTIVE"
private let actionStopSession = "STOP_SESSION"

final class NotificationManager: NSObject {
  static let shared = NotificationManager()

  var onStopRequested: (() -> Void)?

  private override init() {
    super.init()
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    NSLog("[Notify] Delegate set: %@", center.delegate != nil ? "YES" : "NO")

    let stop = UNNotificationAction(
      identifier: actionStopSession,
      title: "Stop Session",
      options: [.destructive]
    )
    let category = UNNotificationCategory(
      identifier: categoryStreamActive,
      actions: [stop],
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([category])
    NSLog("[Notify] Category registered: %@", categoryStreamActive)
  }

  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      NSLog("[Notify] Permission result — granted=%@ error=%@",
            granted ? "YES" : "NO",
            error?.localizedDescription ?? "none")
    }
  }

  func sendSessionActiveInBackground(jarvisLive: Bool) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      NSLog("[Notify] sendActive — authStatus=%d alertSetting=%d lockScreenSetting=%d",
            settings.authorizationStatus.rawValue,
            settings.alertSetting.rawValue,
            settings.lockScreenSetting.rawValue)

      guard settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional else {
        NSLog("[Notify] sendActive — not authorized, aborting")
        return
      }

      let content = UNMutableNotificationContent()
      content.title = jarvisLive ? "Jarvis is Listening" : "Stream Running in Background"
      content.body = jarvisLive
        ? "Jarvis is active and listening. Speak normally."
        : "Your glasses stream is running while the screen is off."
      content.sound = nil
      content.categoryIdentifier = categoryStreamActive

      // 1-second delay: iOS suppresses notifications with trigger=nil sent at the
      // exact moment an app enters background.
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
      let request = UNNotificationRequest(
        identifier: "stream-active-bg",
        content: content,
        trigger: trigger
      )

      NSLog("[Notify] Adding request id=stream-active-bg category=%@ jarvisLive=%@",
            categoryStreamActive, jarvisLive ? "YES" : "NO")

      center.add(request) { error in
        if let error {
          NSLog("[Notify] add failed: %@", error.localizedDescription)
        } else {
          NSLog("[Notify] add succeeded — notification scheduled in 1s")
        }
      }
    }
  }

  func sendStreamEnded() {
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: ["stream-active-bg"])
    center.removePendingNotificationRequests(withIdentifiers: ["stream-active-bg"])
    NSLog("[Notify] sendStreamEnded — removed active banner")

    let content = UNMutableNotificationContent()
    content.title = "Stream Ended"
    content.body = "Your Jarvis session has stopped."
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "stream-ended-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil
    )
    center.add(request) { error in
      if let error {
        NSLog("[Notify] sendStreamEnded add failed: %@", error.localizedDescription)
      } else {
        NSLog("[Notify] sendStreamEnded add succeeded")
      }
    }
  }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    NSLog("[Notify] willPresent id=%@", notification.request.identifier)
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSLog("[Notify] didReceive action=%@ id=%@",
          response.actionIdentifier, response.notification.request.identifier)
    if response.actionIdentifier == actionStopSession {
      DispatchQueue.main.async { self.onStopRequested?() }
    }
    completionHandler()
  }
}
