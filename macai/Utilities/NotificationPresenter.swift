//
//  NotificationPresenter.swift
//  macai
//
//  Created by Codex on 19.09.2025.
//

import Foundation
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()
    var onAuthorizationGranted: (() -> Void)?

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            DispatchQueue.main.async {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.onAuthorizationGranted?()
                    }
                }
            }
        }
    }

    /// For existing users who were authorized without .badge, re-request authorization
    /// to register the badge capability with macOS.
    func enableBadgeForExistingUsers() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized && settings.badgeSetting != .enabled {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                DispatchQueue.main.async {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        if granted {
                            self.onAuthorizationGranted?()
                            self.enqueueNotification(
                                center: center,
                                identifier: identifier,
                                title: title,
                                body: body,
                                completion: completion
                            )
                        }
                        else {
                            completion?(false)
                        }
                    }
                }
            case .denied:
                completion?(false)
            default:
                self.enqueueNotification(
                    center: center,
                    identifier: identifier,
                    title: title,
                    body: body,
                    completion: completion
                )
            }
        }
    }

    private func enqueueNotification(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        completion: ((Bool) -> Void)?
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            center.add(request) { error in
                completion?(error == nil)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
