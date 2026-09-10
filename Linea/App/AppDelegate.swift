//
//  AppDelegate.swift
//  Linea
//
//  Exists for one reason: when the user taps «Закрываем сейчас» or «Переносим»
//  on a notification, iOS delivers that answer to the app delegate. Without
//  this the 14:30 nudge would be a message the user cannot answer.
//

import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by the app once the container exists.
    weak var intelligence: IntelligenceStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show the nudge even while the app is open — the card and the banner say
    /// the same thing, and the user should not have to guess which is current.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = NudgeScheduler.response(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else { return }
        await intelligence?.handleNotification(action)
    }
}
